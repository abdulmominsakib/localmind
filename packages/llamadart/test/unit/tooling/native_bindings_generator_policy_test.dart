@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ffigen/ffigen.dart' as ffigen;
// The locked dev tool exposes raw AST transformation only internally. These
// imports exercise its real opacity/by-value policy without parsing C headers.
// ignore: implementation_imports
import 'package:ffigen/src/code_generator.dart' as cg;
// ignore: implementation_imports
import 'package:ffigen/src/code_generator/scope.dart' as scopes;
// ignore: implementation_imports
import 'package:ffigen/src/context.dart' as generator;
// ignore: implementation_imports
import 'package:ffigen/src/header_parser/parser.dart' as parser;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// Context's production constructor opens libclang. The transformer needs only
// this in-memory state; any unexpected parser/native access fails this test.
final class _AstContext implements generator.Context {
  _AstContext(this.config);

  @override
  final ffigen.FfiGenerator config;

  @override
  final Logger logger = Logger.detached('synthetic-binding-policy');

  // Compound construction checks Objective-C imports even for C structs.
  @override
  late final cg.ObjCBuiltInFunctions objCBuiltInFunctions =
      cg.ObjCBuiltInFunctions(
        this,
        // ignore: deprecated_member_use
        config.objectiveC?.generateForPackageObjectiveC ?? false,
      );

  @override
  final generator.LibraryImports libs = generator.LibraryImports();

  @override
  final scopes.Scope rootScope = scopes.Scope.createRoot('root');

  @override
  final scopes.Scope rootObjCScope = scopes.Scope.createRoot('objc');

  @override
  final scopes.Scope rootCppScope = scopes.Scope.createRoot('cpp');

  @override
  late generator.ExtraSymbols extraSymbols;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Synthetic AST policy test cannot access ${invocation.memberName}',
  );
}

({cg.Struct file, cg.Struct params, String output}) _transform({
  bool fullDependencies = false,
  bool includeFile = false,
  String? includeDependency,
  bool fileByValue = false,
  bool fileArrayByValue = false,
}) {
  final config =
      jsonDecode(jsonEncode(loadYaml(File('ffigen.yaml').readAsStringSync())))
          as Map<String, dynamic>;
  // YAML parsing eagerly discovers LLVM. This deliberately non-library path
  // suppresses that search; the strict AST context never opens it. A future
  // attempt to parse C or load libclang must fail instead of using host tools.
  config['llvm-path'] = [File('ffigen.yaml').absolute.path];
  final structs = config['structs'] as Map<String, dynamic>;
  if (fullDependencies) {
    structs['dependency-only'] = 'full';
  }
  if (includeFile) {
    (structs['exclude'] as List<dynamic>).remove('_IO_FILE');
  }
  if (includeDependency != null) {
    final category =
        includeDependency.startsWith('_IO_') &&
            includeDependency != '_IO_lock_t'
        ? structs
        : config['typedefs'] as Map<String, dynamic>;
    (category['exclude'] as List<dynamic>).remove(includeDependency);
  }
  final logger = Logger.detached('synthetic-binding-config');
  final yaml = ffigen.YamlConfig.fromYaml(
    loadYaml(jsonEncode(config)) as YamlMap,
    logger,
    filename: 'ffigen.yaml',
  );
  final context = _AstContext(yaml.configAdapter());
  final integer = cg.NativeType(cg.SupportedNativeType.int32);
  final marker = cg.Struct(
    name: '_IO_marker',
    context: context,
    isIncomplete: true,
  );
  final codecvt = cg.Struct(
    name: '_IO_codecvt',
    context: context,
    isIncomplete: true,
  );
  final wideData = cg.Struct(
    name: '_IO_wide_data',
    context: context,
    isIncomplete: true,
  );
  final lock = cg.Typealias(name: '_IO_lock_t', type: cg.voidType);
  final offset = cg.Typealias(name: '__off_t', type: cg.longType);
  final offset64 = cg.Typealias(name: '__off64_t', type: cg.longType);
  final file = cg.Struct(
    name: '_IO_FILE',
    context: context,
    members: [
      cg.CompoundMember(name: 'private_flags', type: integer),
      cg.CompoundMember(name: 'marker', type: cg.PointerType(marker)),
      cg.CompoundMember(name: 'codecvt', type: cg.PointerType(codecvt)),
      cg.CompoundMember(name: 'wide_data', type: cg.PointerType(wideData)),
      cg.CompoundMember(name: 'lock', type: cg.PointerType(lock)),
      cg.CompoundMember(name: 'old_offset', type: offset),
      cg.CompoundMember(name: 'offset', type: offset64),
    ],
  );
  final fileAlias = cg.Typealias(name: 'FILE', type: file);
  final params = cg.Struct(
    name: 'llama_synthetic_params',
    context: context,
    members: [
      cg.CompoundMember(name: 'token_count', type: integer),
      if (fileByValue) cg.CompoundMember(name: 'stream', type: file),
      if (fileArrayByValue)
        cg.CompoundMember(
          name: 'streams',
          type: cg.ConstantArray(2, file, useArrayType: true),
        ),
    ],
  );
  final function = cg.Func(
    name: 'llama_synthetic_stream',
    returnType: cg.PointerType(fileAlias),
    parameters: [cg.Parameter(name: 'params', type: cg.PointerType(params))],
    loadFromNativeAsset: true,
  );
  final bindings = parser.transformBindings([function, params], context);
  final output = cg.Library.fromContext(
    bindings: bindings,
    context: context,
  ).generate();
  return (file: file, params: params, output: output);
}

void main() {
  test(
    'repo policy keeps pointer-only libc FILE opaque and its alias usable',
    () {
      final result = _transform();
      expect(result.file.isOpaque, isTrue);
      expect(
        result.output,
        contains('final class _IO_FILE extends ffi.Opaque'),
      );
      expect(result.output, contains('typedef FILE = _IO_FILE;'));
      expect(result.output, contains('ffi.Pointer<FILE>'));
      expect(result.output, isNot(contains('private_flags')));
    },
  );

  test('unused libc closure is omitted and each exclusion is causal', () {
    const dependencies = [
      '_IO_codecvt',
      '_IO_marker',
      '_IO_wide_data',
      '_IO_lock_t',
      '__off64_t',
      '__off_t',
    ];
    final output = _transform().output;
    for (final name in dependencies) {
      expect(output, isNot(contains(name)), reason: name);
      expect(
        _transform(includeDependency: name).output,
        contains(name),
        reason: name,
      );
    }
  });

  test(
    'directly included native structs retain fields even behind a pointer',
    () {
      final result = _transform();
      expect(result.params.isOpaque, isFalse);
      expect(result.params.members.map((member) => member.name), [
        'token_count',
      ]);
      expect(result.output, contains('external int token_count;'));
      expect(
        result.output,
        contains('llama_synthetic_params extends ffi.Struct'),
      );
    },
  );

  test('full dependency policy reproduces the unwanted FILE definition', () {
    final result = _transform(fullDependencies: true);
    expect(result.file.isOpaque, isFalse);
    expect(result.output, contains('_IO_FILE extends ffi.Struct'));
    expect(result.output, contains('external int private_flags;'));
  });

  test(
    'including FILE bypasses dependency-only opacity and exposes its fields',
    () {
      final result = _transform(includeFile: true);
      expect(result.file.isOpaque, isFalse);
      expect(result.output, contains('external int private_flags;'));
    },
  );

  test('an excluded struct required by value keeps its complete layout', () {
    final result = _transform(fileByValue: true);
    expect(result.file.isOpaque, isFalse);
    expect(result.output, contains('external int private_flags;'));
    expect(result.output, contains('external _IO_FILE stream;'));
  });

  test('arrays of an excluded struct also preserve by-value fields', () {
    final result = _transform(fileArrayByValue: true);
    expect(result.file.isOpaque, isFalse);
    expect(result.output, contains('external int private_flags;'));
    expect(result.output, contains('ffi.Array<_IO_FILE> streams;'));
  });
}
