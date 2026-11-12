import 'dart:convert';

const String publicLiteRtLmEventPrefix = 'LITERT_PUBLIC_EVENT ';

/// A complete adjacent runtime file bound by the qualification input manifest.
typedef PublicLiteRtLmPayload = ({String name, int bytes, String sha256});

List<PublicLiteRtLmPayload> publicLiteRtLmRuntimeManifest(String source) {
  final value = jsonDecode(source);
  if (value is! List || value.isEmpty) {
    throw const FormatException('Runtime manifest must be a nonempty list.');
  }
  final names = <String>{};
  return [
    for (final entry in value)
      if (entry is Map<String, dynamic> &&
          entry['name'] is String &&
          RegExp(
            r'^[A-Za-z0-9_.-]+\.(?:dylib|so|dll)$',
          ).hasMatch(entry['name'] as String) &&
          names.add(entry['name'] as String) &&
          entry['bytes'] is int &&
          (entry['bytes'] as int) > 0 &&
          entry['sha256'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(entry['sha256'] as String))
        (
          name: entry['name'] as String,
          bytes: entry['bytes'] as int,
          sha256: entry['sha256'] as String,
        )
      else
        throw const FormatException('Invalid or duplicate runtime payload.'),
  ];
}

/// Checks the declared public path and positive result, without inferring a
/// native finish reason that the default service does not expose.
List<String> publicLiteRtLmReceiptErrors(
  List<Map<String, dynamic>> events,
  String route, {
  bool expectedDisabled = false,
  Map<String, dynamic>? profile,
}) {
  final errors = <String>[];
  final identity = events.where((event) => event['stage'] == 'identity');
  if (identity.length != 1 ||
      identity.single['route'] != route ||
      identity.single['injected_runtime_factory'] != false ||
      identity.single['injected_speech_driver'] != false) {
    errors.add('The receipt must identify one uninjected public path.');
  }
  if (events.where((event) => event['stage'] == 'failure').isNotEmpty) {
    errors.add('A failure event cannot qualify a public path.');
  }
  final end = events.where((event) => event['stage'] == 'run_end');
  if (end.length != 1 || end.single['success'] != true) {
    errors.add('A successful owned child completion is required.');
  }
  if (expectedDisabled) {
    final refusal = events.where((event) => event['stage'] == 'disabled');
    if (refusal.length != 1 ||
        refusal.single['mentions_migration'] != true ||
        refusal.single['engine_attempts'] != 0 ||
        end.isEmpty ||
        end.single['qualified_public_v1'] != false) {
      errors.add('Disabled selection must refuse before a fixture engine.');
    }
    return errors;
  }
  if (!events.any(
    (event) =>
        event['stage'] == 'loaded_runtime_payloads' &&
        event['qualified_core_seen'] == true,
  )) {
    errors.add('The bound core must be observed in the public process.');
  }
  if (end.isNotEmpty && end.single['qualified_public_v1'] != true) {
    errors.add('A refusal control is not v1 qualification.');
  }
  if (route == 'speech') {
    final speech = events
        .where((event) => event['stage'] == 'speech_observation')
        .toList();
    if (speech.length != 3 ||
        speech[0]['phase'] != 'stream' ||
        speech[1]['phase'] != 'task' ||
        speech[2]['phase'] != 'cancel' ||
        speech[0]['completion_state'] != 'completed' ||
        speech[0]['transcript'] is! String ||
        speech[1]['transcript'] is! String ||
        speech[2]['cancelled_task_state'] != 'cancelled') {
      errors.add(
        'Default speech stream/task/cancellation observations missing.',
      );
    }
  } else {
    final observations = events.where(
      (event) => event['stage'] == 'chat_observation',
    );
    final passes = events.where((event) => event['stage'] == 'chat_pass');
    final expected = {'1:hello', '1:arithmetic', '2:hello', '2:arithmetic'};
    Set<String> cohort(Iterable<Map<String, dynamic>> values) => {
      for (final event in values) '${event['lifetime']}:${event['case']}',
    };
    if (observations.length != 4 ||
        passes.length != 4 ||
        !cohort(observations).containsAll(expected) ||
        !cohort(passes).containsAll(expected)) {
      errors.add('Both prescribed cases must pass in two engine lifetimes.');
    }
    for (final observation in observations) {
      if (profile == null) {
        errors.add(
          'The fixed profile is required for independent aggregate chat oracles.',
        );
      } else {
        try {
          final encoded = observation['utf8_hex'] as String;
          final bytes = [
            for (var i = 0; i < encoded.length; i += 2)
              int.parse(encoded.substring(i, i + 2), radix: 16),
          ];
          final answer = utf8.decode(bytes);
          final fixture =
              (profile['fixtures'] as Map)[observation['case']] as Map;
          if (!RegExp(
                fixture['regex'] as String,
                caseSensitive: false,
              ).hasMatch(answer.trim()) ||
              [
                '<think>',
                '</think>',
                '<|channel>thought',
                '<channel|>',
              ].any(answer.contains)) {
            errors.add(
              'An observed chat answer fails its fixed profile oracle.',
            );
          }
        } on Object {
          errors.add('An observed chat answer cannot be validated.');
        }
      }
      if (observation['native_settlement'] != 'settled' ||
          observation['utf8_hex'] is! String ||
          !RegExp(
            r'^(?:[0-9a-f]{2})+$',
          ).hasMatch(observation['utf8_hex'] as String) ||
          (route == 'direct' && observation['native_finish'] != 'stop')) {
        errors.add(
          'Chat observations must include bytes, settlement and available finish proof.',
        );
      }
    }
    if (!events.any(
      (event) =>
          event['stage'] == 'cancel' &&
          event['cancel_sent'] == true &&
          event['received_bytes'] is int &&
          (event['received_bytes'] as int) > 0 &&
          event['native_settlement'] == 'settled',
    )) {
      errors.add('Cancellation must follow actual output and settle.');
    }
    if (route == 'direct' &&
        !events.any(
          (event) =>
              event['stage'] == 'cancel' &&
              event['native_finish'] == 'cancelled',
        )) {
      errors.add('The public direct client must report native cancellation.');
    }
  }
  return errors;
}
