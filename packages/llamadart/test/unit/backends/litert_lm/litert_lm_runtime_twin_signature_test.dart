@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

const _nativePath = 'lib/src/backends/litert_lm/litert_lm_runtime.dart';
const _stubPath = 'lib/src/backends/litert_lm/litert_lm_runtime_stub.dart';
const _barrelPath = 'lib/backend.dart';

void main() {
  final native = _Source(
    '${File(_nativePath).readAsStringSync()}\n'
    '${File("lib/src/backends/litert_lm/litert_lm_runtime_facade.dart").readAsStringSync()}',
  );
  final stub = _Source(File(_stubPath).readAsStringSync());
  final shown = _shownNames(File(_barrelPath).readAsStringSync());

  test('the barrel shows names from the runtime twins', () {
    expect(shown, contains('LiteRtLmRuntimeClient'));
  });

  test('both twins declare the same exported types', () {
    final nativeTypes = native.typeNames.where(shown.contains).toSet();
    final stubTypes = stub.typeNames.where(shown.contains).toSet();

    expect(nativeTypes, contains('LiteRtLmRuntimeClient'));
    expect(stubTypes, nativeTypes);
  });

  test('both twins re-export the same libraries', () {
    expect(stub.exports, native.exports);
  });

  for (final name in native.typeNames.where(shown.contains)) {
    test('$name has the same public signatures in both twins', () {
      final nativeSignatures = native.publicSignatures(name);

      expect(nativeSignatures, isNotEmpty);
      expect(stub.publicSignatures(name), unorderedEquals(nativeSignatures));
    });
  }

  test('createConversation signature is extracted with its parameters', () {
    expect(
      native.publicSignatures('LiteRtLmRuntimeClient'),
      contains(
        allOf(
          startsWith('void createConversation({'),
          contains('String? promptTemplate'),
          contains('double temperature = 0.8'),
        ),
      ),
    );
  });

  test('signature extraction ignores bodies, strings, and private members', () {
    final source = _Source(r'''
/// Docs with { braces.
class Sample {
  /// Field docs.
  final Map<String, int> values = {'a{': 1};
  final int _hidden = 0;

  Sample({required this.values, String label = 'x}'}) : assert(true);

  Sample._internal();

  @Deprecated('gone {')
  int count() {
    return '${values.length} }'.length; // }
  }

  bool get ready => _hidden == 0;

  Future<void> run(String input, {int? limit}) async {}

  void _helper() {}
}
''');

    expect(source.publicSignatures('Sample'), [
      'final Map<String, int> values',
      "Sample({required this.values, String label = 'x}'})",
      "@Deprecated('gone {') int count()",
      'bool get ready',
      'Future<void> run(String input, {int? limit})',
    ]);
  });
}

Set<String> _shownNames(String barrel) {
  final match = RegExp(
    "export\\s+'src/backends/litert_lm/litert_lm_runtime_stub\\.dart'"
    "\\s+if\\s*\\(dart\\.library\\.io\\)\\s*"
    "'src/backends/litert_lm/litert_lm_runtime\\.dart'"
    r'\s+show\s+([^;]+);',
  ).firstMatch(barrel);
  if (match == null) {
    fail('$_barrelPath no longer conditionally exports the runtime twins.');
  }
  return match.group(1)!.split(',').map((name) => name.trim()).toSet();
}

final class _Source {
  _Source(String text) {
    final masker = _Masker(text)..run();
    _code = masker.code.toString();
    _structure = masker.structure.toString();
  }

  late final String _code;
  late final String _structure;

  static final _typeDeclaration = RegExp(
    r'^(?:(?:abstract|final|base|sealed|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Za-z]\w*)',
    multiLine: true,
  );

  List<String> get typeNames => [
    for (final match in _typeDeclaration.allMatches(_structure))
      match.group(1)!,
  ];

  List<String> get exports => [
    for (final match in RegExp(
      r'^export\s+([^;]+);',
      multiLine: true,
    ).allMatches(_code))
      _normalize(match.group(1)!),
  ]..sort();

  List<String> publicSignatures(String typeName) {
    final header = RegExp(
      '^(?:(?:abstract|final|base|sealed|interface|mixin)\\s+)*'
      '(?:class|enum|mixin)\\s+$typeName\\b[^{;]*\\{',
      multiLine: true,
    ).firstMatch(_structure);
    if (header == null) {
      return const [];
    }

    final signatures = <String>[];
    var memberStart = header.end;
    var signatureEnd = -1;
    var sawExpression = false;
    var parens = 0;
    var brackets = 0;
    var braces = 0;

    void finishMember(int next) {
      final end = signatureEnd < 0 ? next : signatureEnd;
      final signature = _normalize(_code.substring(memberStart, end));
      if (signature.isNotEmpty && !_isPrivate(signature)) {
        signatures.add(signature);
      }
      memberStart = next;
      signatureEnd = -1;
      sawExpression = false;
    }

    for (var i = header.end; i < _structure.length; i++) {
      final char = _structure[i];
      final topLevel = parens == 0 && brackets == 0 && braces == 0;
      switch (char) {
        case '(':
          parens++;
        case ')':
          parens--;
        case '[':
          brackets++;
        case ']':
          brackets--;
        case '{':
          if (topLevel && signatureEnd < 0) {
            signatureEnd = i;
          }
          braces++;
        case '}':
          if (braces == 0) {
            return signatures;
          }
          braces--;
          if (parens == 0 && brackets == 0 && braces == 0 && !sawExpression) {
            finishMember(i + 1);
          }
        case '=':
          if (topLevel && _isAssignment(i)) {
            sawExpression = true;
            if (signatureEnd < 0) {
              signatureEnd = i;
            }
          }
        case ':':
          if (topLevel && signatureEnd < 0) {
            signatureEnd = i;
          }
        case ';':
          if (topLevel) {
            if (signatureEnd < 0) {
              signatureEnd = i;
            }
            finishMember(i + 1);
          }
      }
    }
    return signatures;
  }

  bool _isAssignment(int index) {
    final before = index > 0 ? _structure[index - 1] : ' ';
    final after = index + 1 < _structure.length ? _structure[index + 1] : ' ';
    return after != '=' && !'=!<>'.contains(before);
  }

  static bool _isPrivate(String signature) {
    final declaration = signature.replaceAll(
      RegExp(r'@\w+(?:\([^)]*\))?\s*'),
      '',
    );
    final callable = RegExp(
      r'([\w.]+)\s*(?:<[^(]*>)?\s*\(',
    ).firstMatch(declaration);
    final name =
        callable?.group(1) ??
        RegExp(r'(\w+)\s*$').firstMatch(declaration)?.group(1);
    return name != null && name.split('.').last.startsWith('_');
  }

  static String _normalize(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'(?<=[(\[{]) '), '')
        .replaceAll(RegExp(r' (?=[)\]},])'), '')
        .replaceAll(RegExp(r',(?=[)\]}])'), '')
        .trim()
        .replaceAll(RegExp(r'\s+(?:async\*?|sync\*)$'), '');
  }
}

final class _Masker {
  _Masker(this._source);

  final String _source;
  final StringBuffer code = StringBuffer();
  final StringBuffer structure = StringBuffer();
  int _index = 0;

  void run() => _scanCode(interpolation: false);

  void _emit(int end, {required bool code, required bool structure}) {
    final limit = end > _source.length ? _source.length : end;
    for (; _index < limit; _index++) {
      final char = _source[_index];
      final keep = char == '\n';
      this.code.write(code || keep ? char : ' ');
      this.structure.write(structure || keep ? char : ' ');
    }
  }

  void _scanCode({required bool interpolation}) {
    var depth = 0;
    while (_index < _source.length) {
      final char = _source[_index];
      if (_source.startsWith('//', _index)) {
        final end = _source.indexOf('\n', _index);
        _emit(end < 0 ? _source.length : end, code: false, structure: false);
      } else if (_source.startsWith('/*', _index)) {
        final end = _source.indexOf('*/', _index + 2);
        _emit(
          end < 0 ? _source.length : end + 2,
          code: false,
          structure: false,
        );
      } else if (char == "'" || char == '"') {
        _scanString();
      } else if (interpolation && char == '}' && depth == 0) {
        return;
      } else {
        if (interpolation && char == '{') {
          depth++;
        } else if (interpolation && char == '}') {
          depth--;
        }
        _emit(_index + 1, code: true, structure: !interpolation);
      }
    }
  }

  void _scanString() {
    final raw =
        _index > 0 &&
        _source[_index - 1] == 'r' &&
        (_index < 2 || !RegExp(r'\w').hasMatch(_source[_index - 2]));
    final quote = _source[_index];
    final delimiter = _source.startsWith(quote * 3, _index) ? quote * 3 : quote;
    _emit(_index + delimiter.length, code: true, structure: false);
    while (_index < _source.length) {
      if (_source.startsWith(delimiter, _index)) {
        _emit(_index + delimiter.length, code: true, structure: false);
        return;
      }
      if (!raw && _source[_index] == r'\') {
        _emit(_index + 2, code: true, structure: false);
      } else if (!raw && _source.startsWith(r'${', _index)) {
        _emit(_index + 2, code: true, structure: false);
        _scanCode(interpolation: true);
        _emit(_index + 1, code: true, structure: false);
      } else {
        _emit(_index + 1, code: true, structure: false);
      }
    }
  }
}
