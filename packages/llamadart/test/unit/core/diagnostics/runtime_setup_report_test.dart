import 'dart:convert';

import 'package:llamadart/src/core/diagnostics/runtime_setup_report.dart';
import 'package:test/test.dart';

LlamaRuntimeSetupReport _report({String raw = '1.2.3'}) =>
    buildRuntimeSetupReport(
      os: raw == '1.2.3' ? 'linux' : raw,
      osVersion: raw,
      architecture: raw == '1.2.3' ? 'x64' : raw,
      dartVersion: raw,
      packageVersion: raw,
      policies: [
        (name: 'llama_cpp', tag: 'v0.7.0-2', publication: 'published'),
      ],
      environment: {
        'LLAMADART_NATIVE_LIB_DIR': raw,
        'LLAMADART_BACKEND_MODULE_DIR': '',
        'HOME': raw,
        'PATH': raw,
        raw: raw,
      },
    );

void main() {
  test('stable schema separates pinned publication and unchecked runtime', () {
    final report = _report();
    final json = report.toJson();
    expect(json.keys.toList(), [
      'schema_version',
      'scope',
      'host',
      'publication_policy',
      'overrides',
      'observations',
      'remediation',
    ]);
    expect(json['schema_version'], 1);
    expect(json['scope'], 'desktop_process_setup');
    expect(json['host'], {
      'os': 'linux',
      'os_version': '1.2.3',
      'architecture': 'x64',
      'dart_version': '1.2.3',
      'llamadart_version': '1.2.3',
      'flutter_version': 'unknown',
    });
    expect(json['publication_policy'], [
      {
        'name': 'llama_cpp',
        'expected_release_tag': 'v0.7.0-2',
        'publication': 'published',
        'loaded_version': 'unknown',
        'native_loading': 'not_checked',
      },
    ]);
    expect(json['overrides'], {
      'LLAMADART_NATIVE_LIB_DIR': 'set',
      'LLAMADART_BACKEND_MODULE_DIR': 'set',
      'LLAMADART_LITERT_LM_LIB_DIR': 'unset',
    });
    expect(json['observations'], {
      'emitted_libraries': 'not_checked',
      'selected_backend': 'unknown',
      'selected_gpu': 'unknown',
      'gpu_usability': 'not_checked',
      'model_capabilities': 'not_checked',
      'inference': 'not_checked',
      'flutter_app_device_browser': 'not_checked',
    });
    expect(jsonDecode(jsonEncode(json)), json);
    expect(jsonEncode(report.toJson()), jsonEncode(json));
  });

  test('snapshot and every nested collection are immutable', () {
    final report = _report();
    final json = report.toJson();
    expect(() => report.runtimes.clear(), throwsUnsupportedError);
    expect(() => report.overrides.clear(), throwsUnsupportedError);
    expect(() => json.clear(), throwsUnsupportedError);
    for (final value in json.values) {
      if (value is Map) {
        expect(() => value.clear(), throwsUnsupportedError);
      } else if (value is List) {
        expect(() => value.clear(), throwsUnsupportedError);
        for (final entry in value.whereType<Map>()) {
          expect(() => entry.clear(), throwsUnsupportedError);
        }
      }
    }
  });

  test('human rendering is concise and labels the limitations', () {
    expect(_report().toText(), '''
llamadart setup report (schema 1; runtime not verified)
Host: linux 1.2.3 / x64
Dart: 1.2.3; llamadart: 1.2.3; Flutter: unknown
llama_cpp: expected v0.7.0-2; publication published; native loading not_checked
LLAMADART_NATIVE_LIB_DIR: set
LLAMADART_BACKEND_MODULE_DIR: set
LLAMADART_LITERT_LM_LIB_DIR: unset
Backend: unknown; GPU, emitted libraries, model and inference: not_checked
POLICY_ONLY: Custom overrides can differ from pinned publication policy.
RUNTIME_UNCHECKED: Validate the intended app/model/backend separately.''');
  });

  for (final canary in [
    '/Users/private-user/secret-model',
    r'C:\Users\private-user\secret-model',
    r'\\private-server\private-share\secret-model',
    'https://private.example/file?token=PRIVATE_TOKEN',
    'Bearer PRIVATE_TOKEN',
    '\u001b[31mPRIVATE_TOKEN\n',
    '1.2.3\n',
    'a' * 70000,
  ]) {
    test('raw metadata and override values never reach either renderer '
        '(${canary.length} chars)', () {
      final report = _report(raw: canary);
      expect(report.operatingSystem, 'unknown');
      expect(report.operatingSystemVersion, 'unknown');
      expect(report.architecture, 'unknown');
      expect(report.dartVersion, 'unknown');
      expect(report.packageVersion, 'unknown');
      for (final output in [jsonEncode(report.toJson()), report.toText()]) {
        expect(output, isNot(contains(canary)));
        expect(output, isNot(contains('PRIVATE_TOKEN')));
        expect(output, isNot(contains('private-user')));
        expect(output, isNot(contains('private-server')));
        expect(output.length, lessThan(4000));
      }
    });
  }

  test('normalizers preserve only bounded version grammar', () {
    expect(normalizeSetupVersion('3.13.1'), '3.13.1');
    expect(normalizeSetupVersion('v0.18.1-4', releaseTag: true), 'v0.18.1-4');
    expect(normalizeSetupVersion('1.2.3+private-token'), 'unknown');
    expect(normalizeSetupOsVersion('Version 26.0 (Build 25A354)'), '26.0');
    expect(normalizeSetupOsVersion('26.0 private-user'), 'unknown');
  });
}
