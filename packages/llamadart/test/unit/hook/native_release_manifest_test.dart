import 'dart:convert';

import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_release_manifest.dart';

const _tag = 'v0.7.0-3';
const _source = 'leehack/llamadart-native@v0.7.0-3 assets.json';

const _cudaSidecar = {
  'module': 'backend-cuda12',
  'platform': 'windows',
  'arch': 'x64',
  'backend': 'cuda',
  'file': 'llamadart-native-windows-x64-cuda12-$_tag.tar.gz',
  'sha256': 'aa',
};

const _core = {
  'module': 'core',
  'platform': 'windows',
  'arch': 'x64',
  'backend': 'core',
  'file': 'llamadart-native-windows-x64-$_tag.tar.gz',
};

NativeReleaseManifest _parse(Map<String, Object?> manifest) =>
    parseNativeReleaseManifest(
      jsonEncode(manifest),
      tag: _tag,
      source: _source,
    );

Matcher _contractError(Object message) => throwsA(
  isA<NativeHookContractException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

void main() {
  test('a manifest without hook_contract_version is contract 1', () {
    final manifest = _parse({
      'tag': 'b8000',
      'artifacts': [_core],
    });
    expect(manifest.hookContractVersion, 1);
    expect(manifest.sidecars, isEmpty);
  });

  test('rejects an object that is neither a contract nor an artifact list', () {
    expect(
      () => _parse({'error': 'blocked'}),
      _contractError(contains('neither hook_contract_version nor artifacts')),
    );
    expect(() => _parse({}), _contractError(contains('not a release')));
  });

  test('reads a contract 2 backend sidecar and ignores core artifacts', () {
    final manifest = _parse({
      'hook_contract_version': 2,
      'artifacts': [_core, _cudaSidecar],
    });

    expect(manifest.hookContractVersion, 2);
    final sidecar = manifest.sidecarFor(bundle: 'windows-x64', backend: 'cuda');
    expect(sidecar, isNotNull);
    expect(sidecar!.archive, 'windows-x64-cuda12');
    expect(sidecar.bundle, 'windows-x64');
    expect(sidecar.backend, 'cuda');
    expect(manifest.sidecarFor(bundle: 'linux-x64', backend: 'cuda'), isNull);
    expect(manifest.sidecarFor(bundle: 'windows-x64', backend: 'hip'), isNull);
  });

  test('contract 2 publishes Windows x64 CUDA only as a sidecar', () {
    final contract2 = _parse({'hook_contract_version': 2});
    final contract1 = _parse({'hook_contract_version': 1});

    expect(
      contract2.publishesOnlyAsSidecar(bundle: 'windows-x64', backend: 'cuda'),
      isTrue,
    );
    expect(
      contract2.publishesOnlyAsSidecar(bundle: 'linux-x64', backend: 'cuda'),
      isFalse,
    );
    expect(
      contract2.publishesOnlyAsSidecar(
        bundle: 'windows-x64',
        backend: 'vulkan',
      ),
      isFalse,
    );
    expect(
      contract1.publishesOnlyAsSidecar(bundle: 'windows-x64', backend: 'cuda'),
      isFalse,
    );
  });

  test('rejects a contract this hook does not implement', () {
    expect(
      () => _parse({'hook_contract_version': 3}),
      _contractError(
        allOf(
          contains(_source),
          contains('requires native hook contract 3'),
          contains('supports only contract 1 or 2'),
          contains('llamadart_native_tag'),
        ),
      ),
    );
    expect(
      () => _parse({'hook_contract_version': 0}),
      _contractError(contains('contract 0')),
    );
  });

  test('rejects a non-integer contract version', () {
    expect(
      () => _parse({'hook_contract_version': '2'}),
      _contractError(contains('non-integer hook_contract_version')),
    );
  });

  test('rejects text that is not a JSON object', () {
    expect(
      () => parseNativeReleaseManifest('{', tag: _tag, source: _source),
      _contractError(contains('is not valid JSON')),
    );
    expect(
      () => parseNativeReleaseManifest('[]', tag: _tag, source: _source),
      _contractError(contains('is not a JSON object')),
    );
    expect(
      () => _parse({'hook_contract_version': 2, 'artifacts': 'none'}),
      _contractError(contains('artifacts is not a list')),
    );
  });

  group('rejects a malformed sidecar', () {
    for (final MapEntry(key: name, value: change)
        in <String, Map<String, Object?>>{
          'without a platform': {'platform': null},
          'with an empty backend': {'backend': ''},
          'for another tag': {
            'file': 'llamadart-native-windows-x64-cuda12-v0.7.0-2.tar.gz',
          },
          'with no archive key': {'file': 'llamadart-native--$_tag.tar.gz'},
        }.entries) {
      test(name, () {
        expect(
          () => _parse({
            'hook_contract_version': 2,
            'artifacts': [
              {..._cudaSidecar, ...change},
            ],
          }),
          _contractError(contains('malformed backend-cuda12 artifact')),
        );
      });
    }

    for (final MapEntry(key: name, value: file) in {
      'outside its bundle': 'llamadart-native-linux-x64-cuda12-$_tag.tar.gz',
      'that is the core bundle': 'llamadart-native-windows-x64-$_tag.tar.gz',
      'with a path separator':
          'llamadart-native-windows-x64-../cuda12-$_tag.tar.gz',
      'with uppercase': 'llamadart-native-windows-x64-CUDA12-$_tag.tar.gz',
    }.entries) {
      test('named $name', () {
        expect(
          () => _parse({
            'hook_contract_version': 2,
            'artifacts': [
              {..._cudaSidecar, 'file': file},
            ],
          }),
          _contractError(contains('which is not named')),
        );
      });
    }

    test('listed twice for one bundle and backend', () {
      expect(
        () => _parse({
          'hook_contract_version': 2,
          'artifacts': [
            _cudaSidecar,
            {
              ..._cudaSidecar,
              'module': 'backend-cuda13',
              'file': 'llamadart-native-windows-x64-cuda13-$_tag.tar.gz',
            },
          ],
        }),
        _contractError(contains('more than one cuda sidecar for windows-x64')),
      );
    });
  });
}
