@TestOn('vm')
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../../support/litert_lm_v1_public_qualification.dart';

void main() {
  final profile = <String, dynamic>{
    'fixtures': {
      'hello': {'regex': r'\bhello\b'},
      'arithmetic': {'regex': r'^(?:3 \+ 4 = )?7[.!]?$'},
    },
  };
  List<Map<String, dynamic>> positive(String route) => [
    {
      'stage': 'identity',
      'route': route,
      'injected_runtime_factory': false,
      'injected_speech_driver': false,
    },
    for (final lifetime in [1, 2])
      for (final name in ['hello', 'arithmetic']) ...[
        {
          'stage': 'chat_observation',
          'lifetime': lifetime,
          'case': name,
          'utf8_hex': name == 'hello' ? '48656c6c6f' : '37',
          'native_settlement': 'settled',
          'native_finish': route == 'direct'
              ? 'stop'
              : 'not_exposed_by_default_service',
        },
        {'stage': 'chat_pass', 'lifetime': lifetime, 'case': name},
      ],
    {
      'stage': 'cancel',
      'cancel_sent': true,
      'received_bytes': 1,
      'native_settlement': 'settled',
      'native_finish': route == 'direct'
          ? 'cancelled'
          : 'not_exposed_by_default_service',
    },
    {'stage': 'loaded_runtime_payloads', 'qualified_core_seen': true},
    {'stage': 'run_end', 'success': true, 'qualified_public_v1': true},
  ];
  for (final route in ['direct', 'service']) {
    test('$route receipt accepts only the complete two-lifetime cohort', () {
      expect(
        publicLiteRtLmReceiptErrors(positive(route), route, profile: profile),
        isEmpty,
      );
      final duplicated = positive(route);
      for (final row in duplicated.where(
        (row) => row['case'] == 'arithmetic',
      )) {
        row['case'] = 'hello';
      }
      expect(
        publicLiteRtLmReceiptErrors(duplicated, route, profile: profile),
        isNotEmpty,
      );
    });
  }
  test(
    'a missing loaded-core observation invalidates positive qualification',
    () {
      final events = positive('direct')
        ..removeWhere((row) => row['stage'] == 'loaded_runtime_payloads');
      expect(
        publicLiteRtLmReceiptErrors(events, 'direct', profile: profile),
        isNotEmpty,
      );
    },
  );
  test('direct finish and raw-byte observations cannot be omitted', () {
    final events = positive('direct');
    events[1]['native_finish'] = null;
    events[1]['utf8_hex'] = 'not-hex';
    expect(
      publicLiteRtLmReceiptErrors(events, 'direct', profile: profile),
      isNotEmpty,
    );
  });
  test(
    'default service does not need an invented native cancellation getter',
    () {
      expect(
        publicLiteRtLmReceiptErrors(
          positive('service'),
          'service',
          profile: profile,
        ),
        isEmpty,
      );
    },
  );
  test('success events cannot override a failed observed semantic oracle', () {
    final events = positive('direct');
    events.firstWhere(
      (row) =>
          row['stage'] == 'chat_observation' && row['case'] == 'arithmetic',
    )['utf8_hex'] = '32';
    expect(
      publicLiteRtLmReceiptErrors(events, 'direct', profile: profile),
      isNotEmpty,
    );
  });
  test('runtime manifest preserves every exact file identity', () {
    final rows = publicLiteRtLmRuntimeManifest(
      jsonEncode([
        {'name': 'libLiteRtLm.dylib', 'bytes': 123, 'sha256': 'a' * 64},
        {'name': 'libLiteRt.so', 'bytes': 456, 'sha256': 'b' * 64},
      ]),
    );
    expect(rows.map((row) => row.name), ['libLiteRtLm.dylib', 'libLiteRt.so']);
    expect(rows.last.bytes, 456);
  });
  for (final bad in [
    '[]',
    '{}',
    jsonEncode([
      {'name': '../core.so', 'bytes': 1, 'sha256': 'a' * 64},
    ]),
    jsonEncode([
      {'name': 'core.so', 'bytes': 0, 'sha256': 'a' * 64},
    ]),
    jsonEncode([
      {'name': 'core.so', 'bytes': 1, 'sha256': 'bad'},
    ]),
    jsonEncode(
      List.filled(2, {'name': 'core.so', 'bytes': 1, 'sha256': 'a' * 64}),
    ),
  ]) {
    test('malformed or incomplete manifest refuses $bad', () {
      expect(() => publicLiteRtLmRuntimeManifest(bad), throwsFormatException);
    });
  }
  List<Map<String, dynamic>> disabled() => [
    {
      'stage': 'identity',
      'route': 'direct',
      'injected_runtime_factory': false,
      'injected_speech_driver': false,
    },
    {'stage': 'disabled', 'mentions_migration': true, 'engine_attempts': 0},
    {'stage': 'run_end', 'success': true, 'qualified_public_v1': false},
  ];
  test(
    'disabled receipt is a refusal control and never positive qualification',
    () {
      expect(
        publicLiteRtLmReceiptErrors(
          disabled(),
          'direct',
          expectedDisabled: true,
        ),
        isEmpty,
      );
      expect(publicLiteRtLmReceiptErrors(disabled(), 'direct'), isNotEmpty);
    },
  );
  test('an injected factory cannot be recorded as a default public path', () {
    final events = disabled();
    events.first['injected_runtime_factory'] = true;
    expect(
      publicLiteRtLmReceiptErrors(events, 'direct', expectedDisabled: true),
      isNotEmpty,
    );
  });
  test('creating an engine invalidates the disabled gate', () {
    final events = disabled();
    events[1]['engine_attempts'] = 1;
    expect(
      publicLiteRtLmReceiptErrors(events, 'direct', expectedDisabled: true),
      isNotEmpty,
    );
  });
  test('failure events invalidate even a later successful end', () {
    final events = disabled()..insert(1, {'stage': 'failure'});
    expect(
      publicLiteRtLmReceiptErrors(events, 'direct', expectedDisabled: true),
      isNotEmpty,
    );
  });
}
