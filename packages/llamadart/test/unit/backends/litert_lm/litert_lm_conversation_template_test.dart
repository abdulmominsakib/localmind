@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:test/test.dart';

Future<String> _compileFixture(Directory dir, List<String> defines) async {
  final library = '${dir.path}/fixture.${Platform.isMacOS ? 'dylib' : 'so'}';
  final result = await Process.run('cc', [
    '-shared',
    '-fPIC',
    ...defines,
    'test/fixtures/litert_lm/conversation_template.c',
    '-o',
    library,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return library;
}

void main() {
  for (final legacy in [false, true]) {
    test('native conversation template setter, legacy=$legacy', () async {
      final dir = await Directory.systemTemp.createTemp('litert_template_');
      final library = await _compileFixture(dir, [
        if (legacy) '-DOMIT_TEMPLATE_SETTER',
      ]);
      final client = LiteRtLmRuntimeClient(libraryPath: library);
      try {
        await client.initialize(modelPath: 'fixture.litertlm', backend: 'cpu');
        if (legacy) {
          expect(
            () => client.createConversation(
              promptTemplate: 'required',
              npuBackend: true,
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('litert_lm_conversation_config_set_prompt_template'),
                  contains('cannot set a conversation template'),
                  contains('raw prompt generation'),
                  contains('litert-lm-native $liteRtLmReleaseTag'),
                ),
              ),
            ),
          );
          // A runtime without this optional setter still supports requests
          // which preserve its native model template.
          client.createConversation(npuBackend: true);
          expect(
            client.renderMessageToString({'role': 'user', 'content': 'Hi'}),
            '',
          );
        } else {
          const template = '{{ messages }}\n<think>\n\n</think>\n\n';
          const system =
              'Keep literal JSON: {"content":"hello"}\n'
              'and Unicode: 안녕';
          client.createConversation(
            promptTemplate: template,
            systemMessage: system,
            npuBackend: true,
          );
          final readSystem = DynamicLibrary.open(library)
              .lookupFunction<
                Pointer<Utf8> Function(),
                Pointer<Utf8> Function()
              >('fixture_system_message');
          expect(jsonDecode(readSystem().toDartString()), system);
          expect(
            client.renderMessageToString({'role': 'user', 'content': 'Hi'}),
            template,
          );
          client.createConversation(npuBackend: true);
          expect(
            client.renderMessageToString({'role': 'user', 'content': 'Hi'}),
            '',
          );
        }
      } finally {
        client.dispose();
        await dir.delete(recursive: true);
      }
    });

    test(
      'reports whether the runtime renders messages, legacy=$legacy',
      () async {
        final dir = await Directory.systemTemp.createTemp('litert_render_');
        final library = await _compileFixture(dir, [
          if (legacy) '-DOMIT_RENDER',
        ]);
        final client = LiteRtLmRuntimeClient(libraryPath: library);
        try {
          expect(client.supportsMessageRendering, isFalse);
          await client.initialize(
            modelPath: 'fixture.litertlm',
            backend: 'cpu',
          );
          client.createConversation(npuBackend: true);
          expect(client.supportsMessageRendering, !legacy);
          if (legacy) {
            expect(
              () => client.renderMessageToString({'role': 'user'}),
              throwsArgumentError,
            );
          } else {
            expect(client.renderMessageToString({'role': 'user'}), '');
          }
        } finally {
          client.dispose();
          await dir.delete(recursive: true);
        }
      },
    );

    test('zero temperature clamps sampler top-k, legacy=$legacy', () async {
      final dir = await Directory.systemTemp.createTemp('litert_sampler_');
      final library = await _compileFixture(dir, [
        if (legacy) '-DOMIT_OPAQUE_SAMPLER',
      ]);
      final fixture = DynamicLibrary.open(library);
      final topK = fixture.lookupFunction<Int32 Function(), int Function()>(
        'fixture_top_k',
      );
      final temperature = fixture
          .lookupFunction<Float Function(), double Function()>(
            'fixture_temperature',
          );
      final samplerSets = fixture
          .lookupFunction<Int32 Function(), int Function()>(
            'fixture_sampler_sets',
          );
      final client = LiteRtLmRuntimeClient(libraryPath: library);
      try {
        await client.initialize(modelPath: 'fixture.litertlm', backend: 'cpu');
        client.createConversation(temperature: 0);
        expect(topK(), 1);
        expect(temperature(), 0);
        client.createConversation(temperature: 0, topK: 40);
        expect(topK(), 1);
        client.createConversation(temperature: 0, topK: 1);
        expect(topK(), 1);
        client.createConversation(temperature: 0.8, topK: 40);
        expect(topK(), 40);
        expect(temperature(), closeTo(0.8, 1e-6));
        expect(samplerSets(), 4);
        client.createConversation(temperature: 0, topK: 40, npuBackend: true);
        expect(samplerSets(), 4);
      } finally {
        client.dispose();
        await dir.delete(recursive: true);
      }
    });
  }
}
