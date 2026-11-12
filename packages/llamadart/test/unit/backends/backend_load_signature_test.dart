@TestOn('vm')
library;

import 'dart:io';
import 'dart:mirrors';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/native/native_backend.dart';
import 'package:test/test.dart';

void main() {
  for (final type in [
    LlamaBackend,
    BackendModelFormatRouting,
    NativeAutoBackend,
    NativeLlamaBackend,
    LiteRtLmBackend,
    LlamaEngine,
  ]) {
    test('$type load progress callbacks explicitly return void', () {
      final methods = reflectClass(type).declarations.values
          .whereType<MethodMirror>()
          .where(
            (method) => method.parameters.any(
              (parameter) =>
                  parameter.simpleName == #onProgress &&
                  parameter.type is FunctionTypeMirror,
            ),
          );
      expect(methods, isNotEmpty);
      for (final method in methods) {
        final callback =
            method.parameters
                    .singleWhere(
                      (parameter) => parameter.simpleName == #onProgress,
                    )
                    .type
                as FunctionTypeMirror;
        // Structured download/TTS progress already has a separate void contract.
        expect(
          callback.returnType.simpleName,
          #void,
          reason: '$type.${MirrorSystem.getName(method.simpleName)}',
        );
      }
    });
  }

  // Browser-only classes cannot be reflected on the VM. Pin their source
  // signatures as well as exercising progress delivery in Chrome.
  for (final entry in {
    'lib/src/backends/web/web_backend.dart': 2,
    'lib/src/backends/webgpu/webgpu_backend.dart': 2,
    'lib/src/backends/litert_lm/litert_lm_backend_web.dart': 3,
  }.entries) {
    test('${entry.key} has explicit void load progress signatures', () {
      final signatures = RegExp(r'(\w+ )?Function\(double \w+\)\? onProgress')
          .allMatches(File(entry.key).readAsStringSync())
          .map((match) => match.group(0)!)
          .toList();
      expect(signatures, hasLength(entry.value));
      for (final signature in signatures) {
        expect(signature, startsWith('void '));
      }
    });
  }
}
