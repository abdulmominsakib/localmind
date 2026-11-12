"""Causal archive controls for the actual portable verifier."""
import copy
import hashlib
import importlib.util
import json
import pathlib
import sys
import tempfile
import zipfile

root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('evidence', root / 'verify_evidence.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
rows = [dict(name=f'{r}-H{h}E{e}P{p}', exitCode=0, identityValid=True, loadedCpuZero=True)
        for r in ('original', 'fixed') for h in (0, 1) for e in (0, 1) for p in (0, 1)]
rows += [dict(name=f'fixed-H{h}E1P0-alias', exitCode=0, identityValid=True, loadedCpuZero=True) for h in (0, 1)]

def encoded(value):
    return json.dumps(value).encode()

files = {name: b'{}' for name in (
    'candidate-source-binding.json', 'baseline-source-binding.json',
    'candidate-source-files.json', 'baseline-source-files.json',
    'sdk-identity.json', 'sdk-extracted-files.json', 'host.json',
    'peak-space-budget.json', 'normal-AOT-distribution-before.json',
    'normal-AOT-distribution-after.json', 'normal-AOT-distributed-providers.json')}
files.update({
    'transport-selftest.bin': (root / 'transport-selftest.bin').read_bytes(),
    'terminal.json': encoded(dict(head='a' * 40, runId='12', runAttempt='1', harnessFailed=False, completed=True, phase='complete')),
    'override-matrix.json': encoded(rows),
    'windows1649-summary.json': encoded(dict(fixedNormalAotPassed=True, maintainedRegistryIntegrationPassed=True, actualCodeAssetMappingMutationRefusedAndRestored=True, maintainedBindingRefusalTestsPassed=True)),
    'codeasset-mutation-receipt.json': encoded(dict(causalRefusalVerified=True, sourceRestored=True, sourceSha256='b' * 64, restoredSha256='b' * 64)),
    'cases.jsonl': b'\n'.join(encoded(dict(name=row['name'], exitCode=0, timeout=False)) for row in rows),
})
integration_name = 'fixed-maintained-registry-integration'
report = b'real reporter parsing is exercised separately'
files[integration_name + '.events.json'] = report
files[integration_name + '-result.json'] = encoded(dict(
    caseName=integration_name, head='a' * 40, runId='12', runAttempt='1',
    workingDirectory='C:/fixture/core', suitePath='C:/fixture/core/test/integration/windows_ggml_registry_test.dart',
    reportPath='C:/fixture/out/fixed-maintained-registry-integration.events.json',
    testName='an external module directory does not open another ggml registry',
    executedTests=1, skippedTests=0, success=True, reportSha256=hashlib.sha256(report).hexdigest()))
files['cases.jsonl'] += b'\n' + encoded(dict(name=integration_name, exitCode=0, timeout=False))
for row in rows:
    for suffix in ('.stdout.log', '.stderr.log', '-process-environment.json'):
        files[row['name'] + suffix] = b'raw fixture'
files[integration_name + '.stdout.log'] = b'raw stdout'
files[integration_name + '.stderr.log'] = b''
files[integration_name + '-process-environment.json'] = encoded(dict(
    workingDirectory='C:/fixture/core',
    arguments='test -p vm -j 1 --file-reporter "json:C:/fixture/out/fixed-maintained-registry-integration.events.json" test/integration/windows_ggml_registry_test.dart'))

with tempfile.TemporaryDirectory() as work:
    def archive(content, mutate_manifest=False):
        manifest = [dict(relativePath=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()) for name, data in content.items()]
        if mutate_manifest:
            manifest.pop()
        target = pathlib.Path(work) / 'evidence.zip'
        with zipfile.ZipFile(target, 'w') as bundle:
            for name, data in content.items():
                bundle.writestr(name, data)
            bundle.writestr('evidence-manifest.json', encoded(manifest))
        return target

    def verify(content, *, rejected=False, mutate_manifest=False, head='a' * 40):
        try:
            module.verify(archive(content, mutate_manifest), head, '12', '1')
        except (ValueError, KeyError):
            if not rejected:
                raise
        else:
            if rejected:
                raise AssertionError('negative archive accepted')

    verify(files)
    verify(files, rejected=True, mutate_manifest=True)
    verify(files, rejected=True, head='c' * 40)
    for omitted in ('candidate-source-files.json', 'fixed-H0E0P0.stderr.log', integration_name + '.events.json', integration_name + '-result.json'):
        changed = dict(files)
        del changed[omitted]
        verify(changed, rejected=True)
    for key, value in (('skippedTests', 1), ('executedTests', 0), ('reportSha256', 'wrong'), ('workingDirectory', 'C:/foreign/core'), ('head', 'c' * 40)):
        changed = dict(files)
        proof = json.loads(changed[integration_name + '-result.json'])
        proof[key] = value
        changed[integration_name + '-result.json'] = encoded(proof)
        verify(changed, rejected=True)
    for key, value in (('harnessFailed', True), ('completed', False), ('phase', 'setup')):
        changed = dict(files)
        terminal = json.loads(changed['terminal.json'])
        terminal[key] = value
        changed['terminal.json'] = encoded(terminal)
        verify(changed, rejected=True)
    for variant in ('missing-row', 'duplicate-row', 'failed-fixed'):
        changed = dict(files)
        bad_rows = copy.deepcopy(rows)
        if variant == 'missing-row':
            bad_rows.pop()
        elif variant == 'duplicate-row':
            bad_rows[-1] = copy.deepcopy(bad_rows[0])
        else:
            bad_rows[8]['exitCode'] = 1
        changed['override-matrix.json'] = encoded(bad_rows)
        verify(changed, rejected=True)
    changed = dict(files)
    changed['transport-selftest.bin'] = b'x' * 65536
    verify(changed, rejected=True)
print('complete archive accepted; omissions, hashes, run binding and false-success negatives refused')
