"""Verify a downloaded inner archive without extracting untrusted paths."""
import argparse
import hashlib
import json
import pathlib
import zipfile


def verify(archive, head, run_id, run_attempt, *, inventory_only=False):
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        if len(names) != len(set(names)):
            raise ValueError('duplicate archive entry')
        files = {name for name in names if not name.endswith('/')}
        for name in names:
            parts = pathlib.PurePosixPath(name).parts
            if name.startswith('/') or '\\' in name or '..' in parts:
                raise ValueError('unsafe archive path')
        manifest = json.loads(bundle.read('evidence-manifest.json'))
        expected = {entry['relativePath']: entry for entry in manifest}
        if len(expected) != len(manifest):
            raise ValueError('duplicate manifest row')
        if files != set(expected) | {'evidence-manifest.json'}:
            raise ValueError('missing/unlisted evidence')
        for name, entry in expected.items():
            data = bundle.read(name)
            if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise ValueError('evidence bytes/hash mismatch')
        fixture = bundle.read('transport-selftest.bin')
        if len(fixture) != 65536 or hashlib.sha256(fixture).hexdigest() != 'f3b293dead3aba27fe6542a3f97893a5e010e4824ca1753d17f153b1b20a470b':
            raise ValueError('incompressible fixture corrupted')
        terminal = json.loads(bundle.read('terminal.json'))
        if (terminal.get('head'), terminal.get('runId'), terminal.get('runAttempt')) != (head, run_id, run_attempt):
            raise ValueError('run/head binding mismatch')
        if inventory_only:
            return {'integrityVerified': True, 'qualificationVerified': False, 'files': len(files), 'terminal': terminal}
        if terminal.get('harnessFailed') is not False or terminal.get('completed') is not True or terminal.get('phase') != 'complete':
            raise ValueError('setup/failed/incomplete qualification terminal')
        required = {'override-matrix.json', 'windows1649-summary.json',
                    'candidate-source-binding.json', 'baseline-source-binding.json',
                    'candidate-source-files.json', 'baseline-source-files.json',
                    'sdk-identity.json', 'sdk-extracted-files.json', 'host.json',
                    'peak-space-budget.json', 'cases.jsonl',
                    'fixed-maintained-registry-integration.events.json',
                    'fixed-maintained-registry-integration-result.json',
                    'codeasset-mutation-receipt.json', 'normal-AOT-distribution-before.json',
                    'normal-AOT-distribution-after.json', 'normal-AOT-distributed-providers.json'}
        if not required <= files:
            raise ValueError('required evidence omitted')
        rows = json.loads(bundle.read('override-matrix.json'))
        expected_rows = {f'{r}-H{h}E{e}P{p}' for r in ('original', 'fixed')
                         for h in (0, 1) for e in (0, 1) for p in (0, 1)}
        expected_rows |= {'fixed-H0E1P0-alias', 'fixed-H1E1P0-alias'}
        if len(rows) != 18 or {row['name'] for row in rows} != expected_rows:
            raise ValueError('missing/duplicate matrix row')
        cases = [json.loads(line) for line in bundle.read('cases.jsonl').decode('utf-8-sig').splitlines()]
        if len({case['name'] for case in cases}) != len(cases) or any(case['timeout'] for case in cases):
            raise ValueError('duplicate/timed-out subprocess')
        case_names = {case['name'] for case in cases}
        if not expected_rows <= case_names:
            raise ValueError('missing case receipts')
        for case in cases:
            for suffix in ('.stdout.log', '.stderr.log', '-process-environment.json'):
                if case['name'] + suffix not in files:
                    raise ValueError('raw subprocess evidence omitted')
        integration_name = 'fixed-maintained-registry-integration'
        integration = [case for case in cases if case['name'] == integration_name]
        proof = json.loads(bundle.read(integration_name + '-result.json'))
        process = json.loads(bundle.read(integration_name + '-process-environment.json'))
        normalized = lambda value: value.replace('\\', '/').rstrip('/').lower()
        if (len(integration) != 1 or integration[0]['exitCode'] != 0 or
                (proof.get('head'), proof.get('runId'), proof.get('runAttempt')) != (head, run_id, run_attempt) or
                proof.get('caseName') != integration_name or proof.get('success') is not True or
                type(proof.get('executedTests')) is not int or proof['executedTests'] != 1 or
                type(proof.get('skippedTests')) is not int or proof['skippedTests'] != 0 or
                proof.get('testName') != 'an external module directory does not open another ggml registry' or
                f'--file-reporter "json:{proof["reportPath"]}"' not in process['arguments'] or
                normalized(proof['workingDirectory']) != normalized(process['workingDirectory']) or
                normalized(proof['suitePath']) != normalized(proof['workingDirectory']) + '/test/integration/windows_ggml_registry_test.dart' or
                proof.get('reportSha256') != hashlib.sha256(bundle.read(integration_name + '.events.json')).hexdigest()):
            raise ValueError('maintained integration execution proof invalid')
        for row in rows:
            name = row['name']
            if name.startswith('fixed-') or name == 'original-H0E0P0':
                if row.get('exitCode') != 0 or row.get('identityValid') is not True or row.get('loadedCpuZero') is not True:
                    raise ValueError('required model/identity case failed')
        summary = json.loads(bundle.read('windows1649-summary.json'))
        for key in ('fixedNormalAotPassed', 'maintainedRegistryIntegrationPassed',
                    'actualCodeAssetMappingMutationRefusedAndRestored', 'maintainedBindingRefusalTestsPassed'):
            if summary.get(key) is not True:
                raise ValueError('required control incomplete')
        mutation = json.loads(bundle.read('codeasset-mutation-receipt.json'))
        if mutation.get('causalRefusalVerified') is not True or mutation.get('sourceRestored') is not True or mutation.get('sourceSha256') != mutation.get('restoredSha256'):
            raise ValueError('mutant/restore evidence invalid')
        return {'head': head, 'runId': run_id, 'runAttempt': run_attempt,
                'files': len(files), 'qualificationPendingIndependentReview': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive')
    parser.add_argument('--head', required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--run-attempt', required=True)
    parser.add_argument('--inventory-only', action='store_true', help='Verify complete bytes and run binding, including a failed run; makes no qualification claim.')
    args = parser.parse_args()
    print(json.dumps(verify(args.archive, args.head, args.run_id, args.run_attempt, inventory_only=args.inventory_only)))
