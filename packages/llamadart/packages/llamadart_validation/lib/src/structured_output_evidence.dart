import 'dart:convert';

import 'case_catalog.dart';
import 'manifest.dart';

/// Capability flags the structured-output pack expects for [runtime]
/// (`native`, `web` or `litert`).
Map<String, Object?> expectedStructuredCapabilities(
  String runtime, {
  int catalogVersion = validationCatalogVersion,
  ValidationProfile? profile,
  Map environment = const {},
  Map diagnostics = const {},
  Map preparation = const {},
}) {
  final expected = Map<String, Object?>.from(
    (structuredOutputFixture['capabilities'] as Map)[runtime] as Map,
  );
  if (catalogVersion >= 10 && runtime == 'litert') {
    const lock = nativeJsonSchemaCapabilityFixture;
    if (profile == null) {
      expected['structured_output'] = null;
    } else if (profile.runtime != 'litert' ||
        profile.nativeReference ||
        (lock['excluded_family_model_sha256'] as List).contains(
          profile.modelHash,
        ) ||
        profile.backend != lock['requested_backend'] ||
        environment['web'] == true ||
        (environment['os'] != null && environment['os'] != lock['os']) ||
        (environment['build_abi'] != null &&
            environment['build_abi'] != lock['abi']) ||
        (diagnostics['backend_name'] != null &&
            '${diagnostics['backend_name']}'.toLowerCase() !=
                lock['actual_backend'])) {
      expected['structured_output'] = false;
    } else {
      final verified =
          profile.modelHash == lock['model_sha256'] &&
          profile.model['bytes'] == lock['model_bytes'] &&
          preparation['verified'] == true &&
          preparation['sha256'] == lock['model_sha256'] &&
          preparation['bytes'] == lock['model_bytes'] &&
          environment['os'] == lock['os'] &&
          environment['build_os'] == lock['os'] &&
          environment['build_abi'] == lock['abi'] &&
          environment['litert_tag'] == lock['runtime_tag'] &&
          environment['runtime_payload_verified'] == true &&
          RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch('${environment['runtime_bundle_sha256']}') &&
          '${diagnostics['backend_name']}'.toLowerCase() ==
              lock['actual_backend'];
      expected['structured_output'] = verified ? true : null;
    }
  }
  return expected;
}

/// The fixture section for [name].
Map<String, dynamic> structuredFixture(String name) =>
    Map<String, dynamic>.from(structuredOutputFixture[name] as Map);

/// Decodes [text] as JSON, or returns [onError] when it is not JSON.
Object? decodeJsonOr(String text, Object? onError) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return onError;
  }
}

const _notJson = Object();

/// Whether [value] satisfies [schema], checked independently of the library's
/// own output validator. It covers only the keywords the pack's fixtures use:
/// `type`, `enum`, `properties`, `required`, `additionalProperties: false`,
/// `minLength`, `maxLength`, `pattern`, `minimum`, `maximum`, `items`,
/// `minItems` and `maxItems`. Any other keyword fails closed.
bool conformsToFixtureSchema(Object? value, Map schema) {
  const known = {
    'type',
    'enum',
    'properties',
    'required',
    'additionalProperties',
    'minLength',
    'maxLength',
    'pattern',
    'minimum',
    'maximum',
    'items',
    'minItems',
    'maxItems',
  };
  if (schema.keys.any((key) => !known.contains(key))) return false;
  final allowed = schema['enum'];
  if (allowed is List &&
      !allowed.any((item) => canonicalJson(item) == canonicalJson(value))) {
    return false;
  }
  switch (schema['type']) {
    case null:
      return allowed is List;
    case 'null':
      return value == null;
    case 'boolean':
      return value is bool;
    case 'number':
    case 'integer':
      final minimum = schema['minimum'] as num?;
      final maximum = schema['maximum'] as num?;
      return (schema['type'] == 'integer' ? value is int : value is num) &&
          (value as num).isFinite &&
          (minimum == null || value >= minimum) &&
          (maximum == null || value <= maximum);
    case 'string':
      if (value is! String) return false;
      final length = value.runes.length;
      final pattern = schema['pattern'] as String?;
      return length >= (schema['minLength'] as int? ?? 0) &&
          length <= (schema['maxLength'] as int? ?? length) &&
          (pattern == null || RegExp(pattern).hasMatch(value));
    case 'array':
      if (value is! List) return false;
      final items = schema['items'] as Map?;
      return value.length >= (schema['minItems'] as int? ?? 0) &&
          value.length <= (schema['maxItems'] as int? ?? value.length) &&
          (items == null ||
              value.every((item) => conformsToFixtureSchema(item, items)));
    case 'object':
      if (value is! Map || schema['additionalProperties'] != false) {
        return false;
      }
      final properties = schema['properties'] as Map? ?? const {};
      final required = (schema['required'] as List? ?? const []).cast<String>();
      return value.keys.every(properties.containsKey) &&
          required.every(value.containsKey) &&
          value.entries.every(
            (entry) => conformsToFixtureSchema(
              entry.value,
              properties[entry.key] as Map,
            ),
          );
    default:
      return false;
  }
}

/// Whether [output] is a public chat stream that completed in order with
/// exactly [finishReasons].
bool completedStructuredStream(Object? output, List<String> finishReasons) =>
    output is Map &&
    output['error'] == null &&
    output['stream_completed'] == true &&
    output['completion_order_valid'] == true &&
    canonicalJson(output['finish_reasons']) == canonicalJson(finishReasons);

/// Whether the unconstrained [control] output already satisfies the case's
/// predicate, so the fixture cannot show that a constraint was applied.
bool structuredControlConforms(String id, Map<String, dynamic> record) {
  final control = record['control'];
  if (control is! Map || control['content'] is! String) return true;
  final content = control['content'] as String;
  switch (id) {
    case 'S02.json_object':
      return decodeJsonOr(content, _notJson) is Map;
    case 'S03.json_schema':
      final value = decodeJsonOr(content, _notJson);
      return !identical(value, _notJson) &&
          conformsToFixtureSchema(
            value,
            structuredFixture('json_schema')['schema'] as Map,
          );
    case 'S04.grammar':
      return RegExp(
        structuredFixture('grammar')['regex'] as String,
      ).hasMatch(content.trim());
    case 'S05.grammar.lazy':
      final fixture = structuredFixture('lazy_grammar');
      return !content.contains(fixture['trigger'] as String) ||
          RegExp(fixture['regex'] as String).hasMatch(content.trim());
    default:
      return false;
  }
}

/// Lengths of the accumulated proper prefixes of [deltas] that differ from
/// the final content by more than surrounding whitespace.
List<int> structuredPartialLengths(List<String> deltas) {
  final complete = deltas.join();
  final lengths = <int>[];
  var length = 0;
  for (final delta in deltas.take(deltas.length - 1)) {
    length += delta.length;
    if (complete.substring(0, length).trim() != complete.trim()) {
      lengths.add(length);
    }
  }
  return lengths;
}

/// Reconstructs the single streamed tool call in [deltas], or null when they
/// do not form exactly one call with JSON-object arguments.
({String name, Object? arguments})? structuredToolCall(Object? deltas) {
  if (deltas is! List || deltas.isEmpty) return null;
  final name = StringBuffer();
  final arguments = StringBuffer();
  for (final delta in deltas) {
    if (delta is! Map || delta['index'] != 0) return null;
    final function = delta['function'] as Map?;
    name.write(function?['name'] ?? '');
    arguments.write(function?['arguments'] ?? '');
  }
  final decoded = decodeJsonOr(arguments.toString(), _notJson);
  return decoded is Map ? (name: name.toString(), arguments: decoded) : null;
}

bool _rejected(Object? rejection, String type, [String? message]) =>
    rejection is Map &&
    rejection['error_type'] == type &&
    (message == null || rejection['message'] == message);

/// Rechecks a passing structured-output case from its recorded evidence, so a
/// journal cannot claim PASS without the outputs that establish it.
/// [runtime] is `native`, `web` or `litert`.
bool validStructuredCaseEvidence(
  String id,
  Map<String, dynamic> record, {
  required String runtime,
  int catalogVersion = validationCatalogVersion,
  ValidationProfile? profile,
  Map environment = const {},
  Map diagnostics = const {},
  Map preparation = const {},
}) {
  final constrained = record['constrained'];
  final content = constrained is Map ? constrained['content'] : null;
  switch (id) {
    case 'S01.capabilities':
      final expected = expectedStructuredCapabilities(
        runtime,
        catalogVersion: catalogVersion,
        profile: profile,
        environment: environment,
        diagnostics: diagnostics,
        preparation: preparation,
      );
      return expected['structured_output'] != null &&
          canonicalJson(record['reported']) == canonicalJson(expected) &&
          (catalogVersion < 10 ||
              runtime != 'litert' ||
              (record['native_schema_admitted'] ==
                      expected['structured_output'] &&
                  record['diagnostics'] is Map &&
                  (record['diagnostics'] as Map)['backend_name'] ==
                      diagnostics['backend_name']));
    case 'S02.json_object':
      final decoded = content is String ? decodeJsonOr(content, _notJson) : 0;
      return !structuredControlConforms(id, record) &&
          completedStructuredStream(constrained, ['stop']) &&
          decoded is Map &&
          (constrained as Map).containsKey('parsed') &&
          canonicalJson(constrained['parsed']) == canonicalJson(decoded);
    case 'S03.json_schema':
      final decoded = content is String
          ? decodeJsonOr(content, _notJson)
          : _notJson;
      return !structuredControlConforms(id, record) &&
          completedStructuredStream(constrained, ['stop']) &&
          !identical(decoded, _notJson) &&
          conformsToFixtureSchema(
            decoded,
            structuredFixture('json_schema')['schema'] as Map,
          ) &&
          (constrained as Map).containsKey('parsed') &&
          canonicalJson(constrained['parsed']) == canonicalJson(decoded) &&
          record['helper'] is Map &&
          (record['helper'] as Map)['error'] == null &&
          (record['helper'] as Map).containsKey('value') &&
          conformsToFixtureSchema(
            (record['helper'] as Map)['value'],
            structuredFixture('json_schema')['schema'] as Map,
          );
    case 'S04.grammar':
      return !structuredControlConforms(id, record) &&
          completedStructuredStream(constrained, ['stop']) &&
          content is String &&
          RegExp(
            structuredFixture('grammar')['regex'] as String,
          ).hasMatch(content);
    case 'S05.grammar.lazy':
      final fixture = structuredFixture('lazy_grammar');
      final trigger = content is String
          ? content.indexOf(fixture['trigger'] as String)
          : -1;
      return !structuredControlConforms(id, record) &&
          completedStructuredStream(constrained, ['stop']) &&
          trigger > 0 &&
          (content as String).substring(0, trigger).trim().isNotEmpty &&
          RegExp(fixture['regex'] as String).hasMatch(content);
    case 'S06.reject':
      final fixture = structuredFixture('reject');
      final malformed = record['malformed'];
      final mismatch = record['mismatch'];
      final recovery = record['recovery'];
      final mismatchContent = mismatch is Map ? mismatch['content'] : null;
      final generated = mismatchContent is String
          ? decodeJsonOr(mismatchContent, _notJson)
          : _notJson;
      return malformed is Map &&
          completedStructuredStream(malformed, ['stop']) &&
          identical(
            decodeJsonOr('${malformed['content']}', _notJson),
            _notJson,
          ) &&
          _rejected(
            malformed['parse_error'],
            'LlamaInferenceException',
            fixture['malformed_message'] as String,
          ) &&
          completedStructuredStream(mismatch, ['stop']) &&
          !identical(generated, _notJson) &&
          conformsToFixtureSchema(
            generated,
            fixture['generated_schema'] as Map,
          ) &&
          _rejected(
            (mismatch as Map)['parse_error'],
            'LlamaInferenceException',
            fixture['mismatch_message'] as String,
          ) &&
          _rejected(
            record['unsupported_schema'],
            'LlamaUnsupportedException',
          ) &&
          _rejected(
            record['unsupported_response_format'],
            'LlamaUnsupportedException',
          ) &&
          (record['unsupported_response_format'] as Map)['chunks'] == 0 &&
          completedStructuredStream(recovery, ['stop']) &&
          '${(recovery as Map)['content']}'.trim().isNotEmpty;
    case 'S07.stream':
      final output = record['output'];
      if (output is! Map ||
          output['content_deltas'] is! List ||
          output['content'] is! String) {
        return false;
      }
      final deltas = (output['content_deltas'] as List).cast<String>();
      final text = output['content'] as String;
      final decoded = decodeJsonOr(text, _notJson);
      final partials = structuredPartialLengths(deltas);
      final rejections = record['partial_rejections'];
      return completedStructuredStream(output, ['stop']) &&
          deltas.length >= 2 &&
          deltas.join() == text &&
          !identical(decoded, _notJson) &&
          conformsToFixtureSchema(
            decoded,
            structuredFixture('json_schema')['schema'] as Map,
          ) &&
          output.containsKey('parsed') &&
          canonicalJson(output['parsed']) == canonicalJson(decoded) &&
          partials.isNotEmpty &&
          partials.every(
            (length) => identical(
              decodeJsonOr(text.substring(0, length), _notJson),
              _notJson,
            ),
          ) &&
          rejections is List &&
          canonicalJson(rejections.map((e) => (e as Map)['length']).toList()) ==
              canonicalJson(partials) &&
          rejections.every(
            (rejection) => _rejected(rejection, 'LlamaInferenceException'),
          );
    case 'S08.tools.schema':
      final fixture = structuredFixture('tools');
      final output = record['output'];
      final call = output is Map
          ? structuredToolCall(output['tool_call_deltas'])
          : null;
      return completedStructuredStream(output, ['tool_calls']) &&
          call != null &&
          call.name == fixture['name'] &&
          conformsToFixtureSchema(call.arguments, fixture['schema'] as Map);
    default:
      return false;
  }
}
