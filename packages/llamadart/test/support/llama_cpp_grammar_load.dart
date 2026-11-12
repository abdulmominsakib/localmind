export 'package:llamadart/src/core/grammar/llama_cpp_grammar_limits.dart'
    show llamaCppRepetitionRejection;

/// Declared-key sets whose open-object exclusion grammars previously exceeded
/// llama.cpp's repetition limit.
final Map<String, List<String>> largeKeySets = {
  'Kubernetes PodSpec': _podSpecProperties,
  '150 keys': [for (var i = 0; i < 150; i++) 'field_${i}_value'],
  '21 distinct 20-character names': [
    for (var i = 0; i < 21; i++)
      '${String.fromCharCode(0x61 + i)}0123456789abcdefghi',
  ],
  '4 names of 128 characters': [
    for (var i = 0; i < 4; i++)
      '${String.fromCharCode(0x61 + i)}${'0123456789abcdef' * 8}'.substring(
        0,
        128,
      ),
  ],
  '1023 properties': [for (var i = 0; i < 1023; i++) 'p$i'],
};

/// Declared keys whose exclusion rules exceed the per-grammar budget, so the
/// extra-property slot falls back to the plain string key.
final List<String> overBudgetKeySet = [
  for (var i = 0; i < 200; i++)
    'n${i.toString().padLeft(3, '0')}${'abcdefghij' * 10}'.substring(0, 100),
];

/// Item schemas covering primitive, enum, object, nested and union arrays.
const List<Map<String, dynamic>> boundedArrayItemSchemas = [
  {'type': 'string'},
  {'type': 'integer'},
  {
    'enum': ['x', 'y'],
  },
  {
    'type': 'object',
    'properties': {
      'a': {'type': 'integer'},
    },
    'required': ['a'],
    'additionalProperties': false,
  },
  {
    'type': 'array',
    'items': {'type': 'integer'},
  },
  {
    'anyOf': [
      {'type': 'integer'},
      {'type': 'null'},
    ],
  },
];

/// Returns a JSON value that [schema] from [boundedArrayItemSchemas] accepts.
Object? boundedArrayItemValue(Map<String, dynamic> schema) =>
    switch (schema['type']) {
      'string' => 's',
      'integer' => 1,
      'object' => {'a': 1},
      'array' => [1],
      _ => schema.containsKey('enum') ? 'x' : null,
    };

const _podSpecProperties = [
  'activeDeadlineSeconds',
  'affinity',
  'automountServiceAccountToken',
  'containers',
  'dnsConfig',
  'dnsPolicy',
  'enableServiceLinks',
  'ephemeralContainers',
  'hostAliases',
  'hostIPC',
  'hostNetwork',
  'hostPID',
  'hostUsers',
  'hostname',
  'imagePullSecrets',
  'initContainers',
  'nodeName',
  'nodeSelector',
  'os',
  'overhead',
  'preemptionPolicy',
  'priority',
  'priorityClassName',
  'readinessGates',
  'resourceClaims',
  'restartPolicy',
  'runtimeClassName',
  'schedulerName',
  'schedulingGates',
  'securityContext',
  'serviceAccount',
  'serviceAccountName',
  'setHostnameAsFQDN',
  'shareProcessNamespace',
  'subdomain',
  'terminationGracePeriodSeconds',
  'tolerations',
  'topologySpreadConstraints',
  'volumes',
];
