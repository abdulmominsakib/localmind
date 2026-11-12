@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_json_schema_bindings.dart';
import 'package:test/test.dart';

int? _provider;
int? _constraint;
String? _schema;
bool? _enabled;
int _deleted = 0;
final _targets = <int>[];
bool _failCreate = false;

void _setProvider(Pointer<Void> target, Pointer<Int> value) {
  _provider = value.value;
}

void _setConstraint(Pointer<Void> target, int type, Pointer<Utf8> value) {
  _constraint = type;
  _schema = value.toDartString();
}

Pointer<Void> _create() => _failCreate ? nullptr : Pointer.fromAddress(42);
void _enable(Pointer<Void> target, bool enabled) {
  _enabled = enabled;
}

void _delete(Pointer<Void> target) {
  _deleted++;
}

void _thinking(Pointer<Void> target, Pointer<Void> value) {
  _targets.add(target.address);
}

final _addresses = <Pointer<Void>>[
  Pointer.fromFunction<Void Function(Pointer<Void>, Pointer<Int>)>(
    _setProvider,
  ).cast(),
  Pointer.fromFunction<Void Function(Pointer<Void>, Int, Pointer<Utf8>)>(
    _setConstraint,
  ).cast(),
  Pointer.fromFunction<Pointer<Void> Function()>(_create).cast(),
  Pointer.fromFunction<Void Function(Pointer<Void>, Bool)>(_enable).cast(),
  Pointer.fromFunction<Void Function(Pointer<Void>)>(_delete).cast(),
  Pointer.fromFunction<Void Function(Pointer<Void>, Pointer<Void>)>(
    _thinking,
  ).cast(),
  Pointer.fromFunction<Void Function(Pointer<Void>, Pointer<Void>)>(
    _thinking,
  ).cast(),
];

void main() {
  final symbols = Map.fromIterables(LiteRtLmJsonSchemaApi.symbols, _addresses);
  setUp(() {
    _provider = null;
    _constraint = null;
    _schema = null;
    _enabled = null;
    _deleted = 0;
    _targets.clear();
    _failCreate = false;
  });
  for (final missing in LiteRtLmJsonSchemaApi.symbols) {
    test('fails closed when $missing is absent', () {
      expect(
        LiteRtLmJsonSchemaApi.probe(
          (name) => name == missing ? null : symbols[name],
        ),
        isNull,
      );
    });
  }
  test(
    'copies the actual provider and schema wire values and closes temporary thinking configs',
    () {
      final api = LiteRtLmJsonSchemaApi.probe((name) => symbols[name])!;
      api.configure(Pointer.fromAddress(100));
      api.constrain(Pointer.fromAddress(200), '{"type":"object"}');
      expect(_provider, 1);
      expect(_constraint, 2);
      expect(_schema, '{"type":"object"}');
      expect(_enabled, isFalse);
      expect(_targets, [100, 200]);
      expect(_deleted, 2);
    },
  );
  test('native thinking-config allocation failure cannot report success', () {
    _failCreate = true;
    final api = LiteRtLmJsonSchemaApi.probe((name) => symbols[name])!;
    expect(() => api.configure(Pointer.fromAddress(100)), throwsStateError);
    expect(_deleted, 0);
  });
}
