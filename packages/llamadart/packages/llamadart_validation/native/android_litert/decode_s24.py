"""Decode only retained S24 bytes; never infer qualification or contact a service."""
import argparse
from contextlib import ExitStack
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat

from s24_capture import decode_capture

CASES = ['s24.native.launch', 's24.native.gpu-guard', 'public.legacy.gpu-refusal', 's24.native.cpu-corrected']
for route in ('cpu-corrected', 'auto-legacy', 'auto-corrected'):
    CASES += [f'{route}.{lifetime}.{name}' for lifetime in (1, 2) for name in ('hello', 'arithmetic')]
    CASES += [route + '.cancel']
CASES += ['s24.native.gpu-corrected']

def require(value, message):
    if not value: raise ValueError(message)

def digest(raw): return hashlib.sha256(raw).hexdigest()

def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result

def loads(raw):
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite JSON: ' + value)))

def capture(value):
    return decode_capture(value)

def captures(value, key=None):
    result = []
    expected = key in ('capture', 'native_stderr', 'answer_capture', 'stdout', 'stderr')
    require(not expected or isinstance(value, dict), 'Capture object required')
    if isinstance(value, dict):
        if expected or {'bytes', 'sha256'} <= value.keys() and ('base64' in value or 'utf8' in value):
            result.append(capture(value))
        for name, child in value.items(): result += captures(child, name)
    elif isinstance(value, list):
        for child in value: result += captures(child)
    return result

def jsonl(raw, maximum, line_maximum):
    require(len(raw) <= maximum and raw.endswith(b'\n'), 'Truncated/oversized JSONL')
    rows = []; start = 0
    while start < len(raw):
        end = raw.find(b'\n', start)
        # Unicode line separators are capture data; only physical LF frames JSONL.
        body_end = end - 1 if end > start and raw[end - 1] == 13 else end
        require(start < body_end and body_end - start <= line_maximum, 'Empty/oversized JSONL line')
        require(raw.find(b'\r', start, body_end) < 0, 'Bare CR in JSONL frame')
        row = loads(raw[start:body_end].decode('utf-8', errors='strict'))
        require(isinstance(row, dict), 'JSONL record is not an object')
        rows.append(row); start = end + 1
    return rows

def child(row, execution_hash, directory, status):
    rawout, rawerr = capture(row['stdout']), capture(row['stderr'])
    require(len(rawout) <= 2 * 1024 * 1024 and len(rawerr) <= 8 * 1024 * 1024, 'Native capture cap exceeded')
    receipt = row['receipt']; case = row['case_id']
    modes = {'s24.native.launch': 'probe', 's24.native.gpu-guard': 'guard',
             's24.native.cpu-corrected': 'cpu', 's24.native.gpu-corrected': 'gpu'}
    require(case in modes, 'Owned native capture attributed to a public case')
    if status == 'PASS':
        require(type(receipt['exit_code']) is int and receipt['exit_code'] == 0 and receipt['timed_out'] is False and
                receipt['capture_limit_exceeded'] is False and receipt['capture_failed'] is False and
                type(receipt['elapsed_ms']) is int and 0 <= receipt['elapsed_ms'] <= 125000,
                'Native PASS contradicts failed/unsafe process receipt')
    for name, raw in [('stdout.jsonl', rawout), ('stderr.log', rawerr)]:
        lock = receipt['files'][name]
        require(len(raw) == lock['bytes'] and digest(raw) == lock['sha256'], 'Owned child receipt bytes changed')
        require((directory / case / name).is_file() and (directory / case / name).read_bytes() == raw, 'Missing/changed independently retained child raw file')
    # A failed capture is retained as failed evidence, never turned into successful protocol.
    rows = jsonl(rawout, 2 * 1024 * 1024, 64 * 1024)
    require(2 <= len(rows) <= 16, 'Native child record count invalid')
    require(receipt['binding'] == execution_hash and receipt['case_id'] == case and
            type(receipt['pid']) is int and receipt['pid'] > 0, 'Owned child receipt identity differs')
    for number, record in enumerate(rows):
        require(record['schema'] == 1 and record['binding'] == execution_hash and record['case_id'] == case and
                record['pid'] == receipt['pid'] and record['sequence'] == number and
                record['event'] in ('started', 'maps', 'generation', 'finished'), 'Native child protocol identity/order differs')
        for name in ('native_json_hex', 'raw_hex'):
            if name in record:
                require(isinstance(record[name], str) and re.fullmatch(r'(?:[0-9a-f]{2})*', record[name]), 'Malformed native raw hex')
                raw = bytes.fromhex(record[name])
                if name == 'native_json_hex': loads(raw.decode('utf-8'))
    require(rows[0]['mode'] == modes[case], 'Native child mode contradicts fixed case')
    require(rows[0]['event'] == 'started' and rows[-1]['event'] == 'finished' and
            sum(x['event'] == 'started' for x in rows) == sum(x['event'] == 'finished' for x in rows) == 1,
            'Native child lifetime incomplete')
    if status == 'PASS':
        if modes[case] == 'probe':
            require(len(rows) == 2 and rows[-1]['model_free_launch'] is True, 'Native launch PASS lacks model-free completion')
        elif modes[case] == 'guard':
            require(len(rows) == 2 and rows[-1]['guard_refused'] is True and isinstance(rows[-1]['native_error'], str), 'Native guard PASS lacks refusal completion')
        else:
            require(rows[-1]['engine_deleted'] is True and sum(x['event'] == 'maps' for x in rows) == 1,
                    'Native generation PASS lacks mapping/engine completion')
            require([x['fixture'] for x in rows if 'native_json_hex' in x] == ['hello', 'arithmetic'] and
                    [x['fixture'] for x in rows if 'input_tokens' in x] == ['hello', 'arithmetic'],
                    'Native generation PASS lacks original two fixture raw/counter records')
    return {'case_id': case, 'exit_code': receipt['exit_code'], 'records': len(rows),
            'stdout_sha256': digest(rawout), 'stderr_sha256': digest(rawerr),
            'native_generation_jsons': sum('native_json_hex' in x for x in rows)}

def decode(path, binding, *, raw=None):
    if raw is None:
        require(path.stat().st_size <= 16 * 1024 * 1024, 'Journal exceeds original16MiB bound')
        with path.open('rb') as stream:
            raw = stream.read(16 * 1024 * 1024 + 1)
    rows = jsonl(raw, 16 * 1024 * 1024, 16 * 1024 * 1024)
    identities = [row for row in rows if row.get('event') == 'identity']
    require(len(identities) == 1 and rows[0] is identities[0], 'Missing/duplicate/out-of-order identity')
    identity = identities[0]
    require(identity['binding'] == binding and identity['device']['model'] == 'SC-51E' and identity['device']['api'] == 36 and
            'SM8650' in identity['device']['soc'] and identity['device']['build'], 'Wrong source/device/runtime binding')
    require(identity['required_case_ids'] == CASES and identity['injected_runtime_factory'] is False and
            identity['backend_override'] is False and identity['public_finish'] == 'not_exposed_by_default_service', 'Changed public qualifier graph/scope')
    execution_hash = digest(json.dumps(binding, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode())
    sequences = [row['sequence'] for row in rows if 'sequence' in row]
    require(sequences == list(range(len(sequences))), 'Journal sequence gap/duplicate')
    complete = [row for row in rows if row.get('event') == 'complete']
    require(len(complete) == 1, 'Missing/duplicate completion; retain raw partial journal')
    final = complete[0]
    require(set(final['case_statuses']) == set(CASES) and all(x in ('PASS', 'FAIL', 'NOT_RUN') for x in final['case_statuses'].values()), 'Incomplete final case inventory')
    native = []; chunks = {}; results = {}; capture_count = 0
    starts = {}; events = {case: [] for case in CASES}
    complete_seen = False
    for row in rows:
        if row['event'] not in ('identity', 'complete', 'execution_failed'):
            require(type(row.get('sequence')) is int and 'case_id' in row, 'Producer case/stage event lacks ordered sequence/case field')
        require(not complete_seen or row['event'] == 'execution_failed', 'Producer events follow completion')
        if row['event'] == 'complete': complete_seen = True
        capture_count += len(captures(row))
        case = row.get('case_id')
        if case is not None: require(case in CASES, 'Unexpected case id')
        if row['event'] == 'case_started':
            require(case in CASES and case not in starts and case not in results, 'Duplicate/invalid case start')
            starts[case] = row
        if case in events: events[case].append(row)
        if row['event'] in ('owned_child_capture', 'native_answer_observation', 'public_chunk', 'public_observation',
                             'semantic_oracle', 'public_refusal', 'public_cancel', 'case_error', 'native_stderr', 'case_result'):
            require(case in starts and case not in results, 'Case evidence lacks start or follows result')
        if row['event'] == 'owned_child_capture': native.append(child(row, execution_hash, path.parent, final['case_statuses'][case]))
        if row['event'] == 'public_chunk': chunks.setdefault(case, []).append(capture(row['capture']))
        if row['event'] in ('public_observation', 'public_cancel'):
            require(b''.join(chunks.get(case, [])) == capture(row['answer_capture']), 'Public chunk/answer mismatch')
            require(row['native_finish'] == 'not_exposed_by_default_service', 'Public native finish overclaim')
        if row['event'] == 'case_result':
            require(case not in results and row['status'] in ('PASS', 'FAIL'), 'Duplicate/invalid case result')
            results[case] = row['status']
    require(set(starts) == set(results) == {case for case in CASES if final['case_statuses'][case] != 'NOT_RUN'},
            'Reached final statuses require exactly one case_started and case_result; NOT_RUN cannot hide a reached case')
    require(all(final['case_statuses'][case] == status for case, status in results.items()), 'Final status contradicts case result')
    require(final['case_statuses']['s24.native.launch'] == final['case_statuses']['s24.native.gpu-guard'] == 'PASS' and
            final['case_statuses']['s24.native.cpu-corrected'] != 'NOT_RUN', 'Completion lacks mandatory initial native controls')
    group_failures = {row['route'] for row in rows if row['event'] == 'group_failed'}
    require(group_failures <= {'cpu-corrected', 'auto-legacy', 'auto-corrected'}, 'Unknown public group failure')
    dependencies = {case for row in rows if row['event'] == 'dependent_cases_not_run' for case in row['case_ids']}
    require(dependencies <= set(CASES) and all(final['case_statuses'][case] == 'NOT_RUN' for case in dependencies), 'Dependency omission contradicts reached status')
    for case in CASES:
        status = final['case_statuses'][case]
        values = events[case]
        named = lambda event: [row for row in values if row['event'] == event]
        if status == 'NOT_RUN':
            require(case in dependencies or case.split('.')[0] in group_failures or
                    (case == 's24.native.gpu-corrected' and final['case_statuses']['s24.native.cpu-corrected'] == 'FAIL'),
                    'Unexecuted case lacks a producer dependency/group failure')
            continue
        if case.startswith('s24.native.'):
            require(len(named('owned_child_capture')) == 1, 'Reached native case lacks unique raw stdout/stderr capture')
            require(len(named('case_error')) == (1 if status == 'FAIL' else 0), 'Native case_error contradicts result')
            if status == 'PASS' and case.endswith(('cpu-corrected', 'gpu-corrected')):
                require([row['fixture'] for row in named('native_answer_observation')] == ['hello', 'arithmetic'], 'Native PASS lacks two answer observations')
        elif case == 'public.legacy.gpu-refusal':
            require(len(named('native_stderr')) == 1, 'Public refusal lacks retained native stderr')
            raw_stderr = capture(named('native_stderr')[0]['capture'])
            require((path.parent / (case + '.stderr')).is_file() and (path.parent / (case + '.stderr')).read_bytes() == raw_stderr, 'Public refusal raw stderr absent/changed')
            if status == 'PASS': require(len(named('public_refusal')) == 1 and named('public_refusal')[0]['typed_unsupported'] is True, 'Public refusal PASS lacks typed refusal')
        elif status == 'PASS':
            require(named('public_chunk'), 'Public PASS lacks raw chunks')
            if case.endswith('.cancel'):
                require(len(named('public_cancel')) == 1 and named('public_cancel')[0]['cancel_sent'] is True and named('public_cancel')[0]['native_settlement'] == 'settled', 'Cancel PASS lacks completed cancellation')
            else:
                require(len(named('public_observation')) == len(named('semantic_oracle')) == 1, 'Public PASS lacks observation/oracle inventory')
                observation = named('public_observation')[0]
                require('native_stderr' in observation and 'mappings' in observation and observation['native_settlement'] == 'settled', 'Public PASS lacks native capture/settlement')
                capture(observation['native_stderr']); capture(observation['mappings']['capture'])
                require(case.startswith('auto-legacy.') or named('semantic_oracle')[0]['passed'] is True, 'Corrected PASS contradicts producer oracle failure')
    for route in ('cpu-corrected', 'auto-legacy', 'auto-corrected'):
        for lifetime in (1, 2):
            prefix = f'{route}.{lifetime}'
            reached = [case for case in starts if case.startswith(prefix + '.') or (lifetime == 1 and case == route + '.cancel')]
            if not reached: continue
            opened = [row for row in rows if row['event'] == 'lifetime_started' and row['lifetime_id'] == prefix]
            closed = [row for row in rows if row['event'] == 'lifetime_closed' and row['route'] == route and row['lifetime'] == lifetime]
            require(len(opened) == len(closed) == 1 and opened[0]['native_log_empty'] is True, 'Reached public lifetime lacks unique fresh start/closure')
            final_stderr = capture(closed[0]['native_stderr'])
            stderr_path = path.parent / (prefix + '.lifetime.stderr')
            require(stderr_path.is_file() and stderr_path.read_bytes() == final_stderr, 'Public lifetime raw stderr absent/changed')
            for case in reached:
                for row in events[case]:
                    if row['event'] == 'public_observation':
                        require(final_stderr.startswith(capture(row['native_stderr'])), 'Public observed stderr contradicts retained lifetime')
    if final['case_statuses']['s24.native.cpu-corrected'] != 'PASS':
        require(final['case_statuses']['s24.native.gpu-corrected'] == 'NOT_RUN', 'Native GPU ran without native CPU control')
    legacy_failures = [row['case_id'] for row in rows if row['event'] == 'semantic_oracle' and row.get('legacy_observation_only') is True and row['passed'] is False]
    require(final['legacy_semantic_failures'] == legacy_failures, 'Legacy failure inventory contradicts producer oracle observations')
    failed = {case for case, status in results.items() if status == 'FAIL'} | group_failures
    require(set(final['failed_cases']) == failed, 'Final failure inventory contradicts case/group outcomes')
    require(final['unexecuted_required_cases'] == [case for case in CASES if final['case_statuses'][case] == 'NOT_RUN'], 'Missing/unordered NOT_RUN cases')
    if final['case_statuses']['s24.native.gpu-corrected'] != 'PASS':
        require(all(final['case_statuses'][case] == 'NOT_RUN' for case in CASES if case.startswith('auto-corrected')), 'Public corrected auto ran without native GPU gate')
    require(final['gpu_per_request_execution_qualified'] is False and final['public_finish'] == 'not_exposed_by_default_service', 'Unsupported execution/finish claim')
    return {'journal_sha256': digest(raw), 'journal_bytes': len(raw), 'records': len(rows), 'decoded_captures': capture_count,
            'native_captures': native, 'producer_statuses': final['case_statuses'],
            'producer_legacy_semantic_failures': final['legacy_semantic_failures'],
            'unexecuted_required_cases': final['unexecuted_required_cases'], 'qualified': False,
            'semantic_or_placement_assessment': 'NOT_ASSESSED; byte-integrity/protocol checks only'}

# A provider collection normally has two exports; cap aliases independently of bytes.
MAX_JOURNAL_ALIASES = 16
JOURNAL_LIMIT = 16 * 1024 * 1024

def collection_walk_error(error):
    raise error

def file_identity(info):
    # atime changes during our reads; ctime also detects same-size rewrites.
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)

def directory_identity(info):
    # Only collection directories use this snapshot, never shared ancestors.
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)

@dataclass
class JournalCandidate:
    path: Path
    info: object
    parents: tuple


@dataclass
class JournalDiscovery:
    candidates: list
    directories_sha256: str


def journal_aliases(directory, run_id):
    root_info = directory.lstat()
    require(stat.S_ISDIR(root_info.st_mode), 'Invalid collection directory')
    journals = []; directory_hash = hashlib.sha256()
    for parent, directories, files in os.walk(directory, followlinks=False, onerror=collection_walk_error):
        directories.sort()
        parent_path = Path(parent)
        parent_info = parent_path.lstat()
        require(stat.S_ISDIR(parent_info.st_mode), 'Collection directory changed')
        directory_hash.update(json.dumps([parent_path.relative_to(directory).as_posix(),
                                         directory_identity(parent_info)], separators=(',', ':')).encode())
        directory_hash.update(b'\n')
        for name in directories:
            require(not (Path(parent) / name).is_symlink(), 'Symlink directory in collection')
        if 's24-litert-public.jsonl' in files or 's24-litert-public.jsonl' in directories:
            path = Path(parent) / 's24-litert-public.jsonl'
            info = path.lstat()
            require(stat.S_ISREG(info.st_mode), 'Journal alias is not a regular nonsymlink file')
            require(path.parent.name == run_id, 'Foreign run journal alias')
            require(0 < info.st_size <= JOURNAL_LIMIT, 'Empty/oversized journal alias')
            parents = [(directory, root_info)]
            current = directory
            for part in path.parent.relative_to(directory).parts:
                current = current / part
                parent_info = current.lstat()
                require(stat.S_ISDIR(parent_info.st_mode), 'Journal parent is not a nonsymlink directory')
                parents.append((current, parent_info))
            journals.append(JournalCandidate(path, info, tuple(parents)))
            require(len(journals) <= MAX_JOURNAL_ALIASES, 'Journal alias count limit exceeded')
    require(journals, 'Missing run journal')
    return JournalDiscovery(
        sorted(journals, key=lambda candidate: candidate.path.relative_to(directory).as_posix()),
        directory_hash.hexdigest())

@dataclass
class AdmittedJournal:
    candidate: JournalCandidate
    fd: int
    # Each child is checked through its still-open parent, never a followed path.
    parents: tuple

    def verify(self):
        root_fd, root_path, root_info = self.parents[0]
        require(directory_identity(root_path.lstat()) == directory_identity(root_info) ==
                directory_identity(os.fstat(root_fd)), 'Collection directory changed')
        for (parent_fd, _, _), (fd, path, info) in zip(self.parents, self.parents[1:]):
            current = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
            require(directory_identity(current) == directory_identity(info) ==
                    directory_identity(os.fstat(fd)), 'Journal parent directory changed')
        current = os.stat(self.candidate.path.name, dir_fd=self.parents[-1][0], follow_symlinks=False)
        require(file_identity(current) == file_identity(self.candidate.info) ==
                file_identity(os.fstat(self.fd)), 'Journal alias identity/content changed')


def admit_journal(candidate, stack):
    require(all(hasattr(os, name) for name in ('O_NOFOLLOW', 'O_DIRECTORY', 'O_NONBLOCK')) and
            os.open in os.supports_dir_fd and os.stat in os.supports_dir_fd and
            os.stat in os.supports_follow_symlinks,
            'Host lacks required no-follow descriptor admission primitives')
    parents = []
    for path, info in candidate.parents:
        fd = os.open(path if not parents else path.name,
                     os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                     **({} if not parents else {'dir_fd': parents[-1][0]}))
        stack.callback(os.close, fd)
        require(directory_identity(os.fstat(fd)) == directory_identity(info), 'Journal parent directory changed')
        parents.append((fd, path, info))
    # NONBLOCK prevents a concurrently substituted FIFO from hanging before fstat.
    fd = os.open(candidate.path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                 dir_fd=parents[-1][0])
    stack.callback(os.close, fd)
    require(stat.S_ISREG(os.fstat(fd).st_mode), 'Journal alias is not a regular nonsymlink file')
    admitted = AdmittedJournal(candidate, fd, tuple(parents))
    admitted.verify()
    return admitted


def read_journal(journal, *, retain=False):
    journal.verify()
    os.lseek(journal.fd, 0, os.SEEK_SET)
    hashed = hashlib.sha256(); size = 0
    raw = bytearray() if retain else None
    while True:
        chunk = os.read(journal.fd, 64 * 1024)
        if not chunk: break
        size += len(chunk)
        require(size <= JOURNAL_LIMIT, 'Journal alias grew beyond original16MiB bound')
        hashed.update(chunk)
        if retain: raw.extend(chunk)
    journal.verify()
    require(size == journal.candidate.info.st_size, 'Empty/changed journal alias size')
    return {'bytes': size, 'sha256': hashed.hexdigest()}, raw


def read_comparison_block(fd):
    # A regular-file read may legally return fewer bytes before EOF.
    block = bytearray()
    while len(block) < 64 * 1024:
        chunk = os.read(fd, 64 * 1024 - len(block))
        if not chunk: break
        block.extend(chunk)
    return block


def compare_journal_alias(canonical, alias):
    # Both descriptors stay pinned; compare exact bytes in constant-size buffers.
    canonical.verify(); alias.verify()
    os.lseek(canonical.fd, 0, os.SEEK_SET); os.lseek(alias.fd, 0, os.SEEK_SET)
    hashed = hashlib.sha256(); size = 0
    while True:
        left = read_comparison_block(canonical.fd)
        right = read_comparison_block(alias.fd)
        size += len(right)
        require(size <= JOURNAL_LIMIT, 'Journal alias grew beyond original16MiB bound')
        require(left == right, 'Journal aliases differ in bytes/size')
        if not right: break
        hashed.update(right)
    canonical.verify(); alias.verify()
    require(size == canonical.candidate.info.st_size == alias.candidate.info.st_size,
            'Empty/changed journal alias size')
    return {'bytes': size, 'sha256': hashed.hexdigest()}

def inspect_collection(directory, plan):
    result = {'qualified': False, 'journal_present': False, 'strict_raw_decode_complete': False,
              'journal_candidates': [], 'errors': []}
    try:
        discovery = journal_aliases(directory, plan['run_id'])
        journals = discovery.candidates
        result['journal_present'] = True
        result['journal_candidates'] = [candidate.path.relative_to(directory).as_posix() for candidate in journals]
        result['canonical_journal'] = result['journal_candidates'][0]
        result['journal_selection'] = 'lexicographically_first_identical_alias'
        with ExitStack() as stack:
            admitted = [admit_journal(candidate, stack) for candidate in journals]
            canonical = admitted[0]
            first_lock, raw = read_journal(canonical, retain=True)
            locks = [first_lock] + [compare_journal_alias(canonical, alias) for alias in admitted[1:]]
            require(all(lock == first_lock for lock in locks), 'Journal alias hashes/sizes differ')
            result['journal_aliases'] = [dict(path=name, **lock) for name, lock in zip(result['journal_candidates'], locks)]
            decoded = decode(canonical.candidate.path, loads(Path(plan['binding']['path']).read_bytes()), raw=raw)
            require(decoded['journal_bytes'] == first_lock['bytes'] and decoded['journal_sha256'] == first_lock['sha256'],
                    'Journal changed after alias admission')
            # Reject mutation/deletion during comparison or parsing, including canonical.
            for journal, lock in zip(admitted, locks):
                current_lock, _ = read_journal(journal)
                require(current_lock == lock, 'Journal alias bytes changed after admission')
            final_discovery = journal_aliases(directory, plan['run_id'])
            require([candidate.path for candidate in final_discovery.candidates] ==
                    [candidate.path for candidate in journals], 'Journal alias set changed after admission')
            require(all(file_identity(before.info) == file_identity(after.info)
                        for before, after in zip(journals, final_discovery.candidates)),
                    'Journal alias identity/content changed after admission')
            require(final_discovery.directories_sha256 == discovery.directories_sha256,
                    'Collection directory contents changed after admission')
            for journal in admitted: journal.verify()
        result['decoded'] = decoded
        result['strict_raw_decode_complete'] = True
    except (ValueError, KeyError, TypeError, OSError, UnicodeError) as error:
        result['errors'].append({'type': type(error).__name__, 'message': str(error)})
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--journal', type=Path, required=True)
    parser.add_argument('--binding', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(decode(args.journal, loads(args.binding.read_bytes())), indent=2))
