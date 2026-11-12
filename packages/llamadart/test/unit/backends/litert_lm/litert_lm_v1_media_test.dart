@TestOn('vm && (mac-os || linux)')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

Uint8List _protoField(int field, List<int> value) =>
    Uint8List.fromList([(field << 3) | 2, ..._varint(value.length), ...value]);

List<int> _varint(int value) {
  final bytes = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    bytes.add((rest & 0x7f) | 0x80);
    rest >>= 7;
  }
  return bytes..add(rest);
}

/// The `LlmMetadata` protobuf of a bundle whose template is [template].
Uint8List _metadata(String? template) => Uint8List.fromList([
  // start_token, a nested message, then max_num_tokens, a varint.
  ..._protoField(1, [0x0a, 0x01, 0x41]),
  0x28, 0x80, 0x20,
  if (template != null) ..._protoField(7, utf8.encode(template)),
]);

/// A `.litertlm` file with [sections] laid out after a FlatBuffers header
/// that [headerPadding] unused bytes follow.
Uint8List _bundle(
  List<({int type, Uint8List data})> sections, {
  int headerPadding = 0,
}) {
  const headerStart = 32;
  // Root offset, root vtable and table, section-metadata vtable and table,
  // then the vector of section objects.
  final objectsStart = 44 + 4 * sections.length;
  final headerEnd =
      headerStart + objectsStart + 36 * sections.length + headerPadding;
  var dataOffset = headerEnd + 16;

  final header = ByteData(headerEnd - headerStart - headerPadding);
  header.setUint32(0, 12, Endian.little);
  header.setUint16(4, 8, Endian.little);
  header.setUint16(6, 12, Endian.little);
  header.setUint16(10, 8, Endian.little);
  header.setInt32(12, 8, Endian.little);
  header.setUint32(20, 12, Endian.little);
  header.setUint16(24, 6, Endian.little);
  header.setUint16(26, 8, Endian.little);
  header.setUint16(28, 4, Endian.little);
  header.setInt32(32, 8, Endian.little);
  header.setUint32(36, 4, Endian.little);
  header.setUint32(40, sections.length, Endian.little);

  final body = BytesBuilder();
  for (var i = 0; i < sections.length; i++) {
    final vtable = objectsStart + 36 * i;
    final table = vtable + 12;
    final slot = 44 + 4 * i;
    header.setUint32(slot, table - slot, Endian.little);
    header.setUint16(vtable, 12, Endian.little);
    header.setUint16(vtable + 2, 24, Endian.little);
    header.setUint16(vtable + 6, 8, Endian.little);
    header.setUint16(vtable + 8, 16, Endian.little);
    header.setUint16(vtable + 10, 4, Endian.little);
    header.setInt32(table, 12, Endian.little);
    header.setUint8(table + 4, sections[i].type);
    header.setUint64(table + 8, dataOffset, Endian.little);
    dataOffset += sections[i].data.length;
    header.setUint64(table + 16, dataOffset, Endian.little);
    body.add(sections[i].data);
  }

  final prefix = ByteData(headerStart);
  prefix.buffer.asUint8List().setAll(0, ascii.encode('LITERTLM'));
  prefix.setUint32(8, 1, Endian.little);
  prefix.setUint32(12, 7, Endian.little);
  prefix.setUint64(24, headerEnd, Endian.little);
  return (BytesBuilder()
        ..add(prefix.buffer.asUint8List())
        ..add(header.buffer.asUint8List())
        ..add(Uint8List(headerPadding + 16))
        ..add(body.takeBytes()))
      .takeBytes();
}

void main() {
  late Directory directory;
  late DynamicLibrary library;
  final variants = <String, DynamicLibrary>{};
  var nextFile = 0;
  int integer(String name, [DynamicLibrary? lib]) => (lib ?? library)
      .lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void set(String name, int value, [DynamicLibrary? lib]) =>
      (lib ?? library).lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  String text(String name) => library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'fixture_$name',
      )()
      .toDartString();
  String preface() => library
      .lookupFunction<Pointer<Utf8> Function(Int), Pointer<Utf8> Function(int)>(
        'fixture_preface',
      )(1)
      .toDartString();
  File model({int family = 8, List<int> config = const []}) {
    final bytes = Uint8List.fromList([
      ..._metadata(null),
      ..._protoField(6, _protoField(family, config)),
    ]);
    return File('${directory.path}/model${nextFile++}.litertlm')
      ..writeAsBytesSync(_bundle([(type: 5, data: bytes)]));
  }

  void emit(String? json, {bool finalChunk = false, DynamicLibrary? lib}) {
    final value = json?.toNativeUtf8(allocator: calloc) ?? nullptr;
    try {
      (lib ?? library).lookupFunction<
        Void Function(Pointer<Utf8>, Bool, Int),
        void Function(Pointer<Utf8>, bool, int)
      >('fixture_client_emit')(value, finalChunk, 1);
    } finally {
      if (value != nullptr) calloc.free(value);
    }
  }

  Future<void> waitForSend(int before) async {
    final deadline = Stopwatch()..start();
    while (integer('sends') == before) {
      if (deadline.elapsed > const Duration(seconds: 3)) {
        fail('native send not reached');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<LiteRtLmV1RuntimeClient> client({
    File? input,
    DynamicLibrary? lib,
    bool image = true,
    bool audio = true,
    int? imageCount,
  }) async {
    final result = LiteRtLmV1RuntimeClient(lib ?? library);
    addTearDown(() async {
      if (result.nativeSettlement == LiteRtLmNativeSettlement.pending) {
        result.cancel();
        emit(null, finalChunk: true);
        while (result.nativeSettlement == LiteRtLmNativeSettlement.pending) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      result.dispose();
    });
    await result.initialize(
      modelPath: (input ?? model()).path,
      backend: 'cpu',
      visionBackend: image ? 'cpu' : null,
      audioBackend: audio ? 'cpu' : null,
      maxNumImages: imageCount,
      speculativeDecoding: false,
      numberOfThreads: 2,
    );
    return result;
  }

  Map<String, dynamic> message(
    String type, {
    String? path,
    String? blob,
    String role = 'user',
  }) => {
    'role': role,
    'content': [
      {'type': type, 'path': ?path, 'blob': ?blob},
    ],
  };
  Future<void> complete(Stream<String> stream, {DynamicLibrary? lib}) async {
    final output = stream.toList();
    emit(
      '{"role":"assistant","content":[{"type":"text","text":"fixture answer"}]}',
      finalChunk: true,
      lib: lib,
    );
    expect((await output).join(), 'fixture answer');
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_media_');
    for (final entry in {
      'main': '',
      'visual': 'OMIT_VISUAL_BUDGET',
      'modality': 'OMIT_METADATA=3',
      'old': 'MEDIA_API_MAJOR=0',
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final built = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (entry.value.isNotEmpty) '-D${entry.value}',
        'test/fixtures/litert_lm/c_api_v1_media.c',
        '-o',
        path,
      ]);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      variants[entry.key] = DynamicLibrary.open(path);
    }
    library = variants['main']!;
  });
  setUp(() {
    set('fail', 0);
    set('metadata_flags', 7);
    set('metadata_fail', 0);
    set('media_inference', 0);
  });
  tearDownAll(() => directory.delete(recursive: true));

  test(
    'native encoded image/audio active payloads and Gemma4 budget survive copied buffers',
    () async {
      final adapter = await client(imageCount: 2);
      adapter.createConversation();
      expect(adapter.resolveDefaultVisualTokenBudget(256), 256);
      for (final type in ['image', 'audio']) {
        final payload = message(type, blob: base64Encode([0, 1, 254, 255]));
        final stream = adapter.generateMessageJson(
          jsonEncode(payload),
          visualTokenBudget: type == 'image' ? 256 : null,
        );
        expect(jsonDecode(text('message')), payload);
        expect(integer('media_budget'), type == 'image' ? 256 : -1);
        await complete(stream);
      }
      expect(integer('media_hint_calls'), 0);
    },
  );

  test(
    'mixed local path history keeps user/assistant roles and snapshots every image',
    () async {
      final adapter = await client(imageCount: 3);
      final path = File('${directory.path}/café.png')
        ..writeAsBytesSync([1, 2, 3]);
      final history = [
        message('image', path: path.path),
        message('image', blob: 'AQID', role: 'assistant'),
        message('audio', blob: 'BAUG'),
      ];
      final expected = jsonDecode(jsonEncode(history));
      adapter.createConversation(messages: history);
      (history.first['content'] as List).clear();
      expect(jsonDecode(preface()), expected);
      expect(integer('media_hint_calls'), 0);
      await complete(adapter.generate('now'));
      adapter.createConversation(
        messages: [
          message('image', blob: 'AQID'),
          message('image', blob: 'BAUG'),
        ],
      );
      expect((jsonDecode(preface()) as List).length, 2);
      await complete(adapter.generate('again'));
    },
  );

  for (final entry in {
    'Gemma3': 4,
    'Gemma3n': 2,
    'FastVLM': 9,
    'LFM2': 11,
    'MiniCPM5': 12,
    'MiniCPMV4': 13,
  }.entries) {
    test(
      '${entry.key} image route never claims a Gemma4 visual constraint',
      () async {
        final adapter = await client(input: model(family: entry.value));
        adapter.createConversation();
        expect(adapter.resolveDefaultVisualTokenBudget(256), isNull);
        expect(
          () => adapter.generateMessageJson(
            jsonEncode(message('image', blob: 'AQID')),
            visualTokenBudget: 256,
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await complete(
          adapter.generateMessageJson(
            jsonEncode(message('image', blob: 'AQID')),
          ),
        );
      },
    );
  }

  test('generic media needs declared processor modality switches', () async {
    final allowed = await client(
      input: model(family: 1, config: [0x18, 1, 0x20, 1]),
    );
    allowed.createConversation();
    expect(allowed.resolveDefaultVisualTokenBudget(256), isNull);
    await complete(
      allowed.generateMessageJson(jsonEncode(message('audio', blob: 'AQID'))),
    );
    allowed.dispose();
    final denied = await client(input: model(family: 1));
    denied.createConversation();
    expect(
      () => denied.generateMessageJson(
        jsonEncode(message('image', blob: 'AQID')),
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  for (final flags in [1, 3, 5]) {
    test(
      'loaded native modality flags $flags gate history before allocation',
      () async {
        set('metadata_flags', flags);
        final adapter = await client();
        final type = flags == 3 ? 'audio' : 'image';
        final before = integer('created');
        expect(
          () => adapter.createConversation(
            messages: [message(type, blob: 'AQID')],
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(integer('created'), before);
      },
    );
  }

  test(
    'missing encoder and unsupported Qwen processor refuse media without send',
    () async {
      final noEncoder = await client(image: false);
      noEncoder.createConversation();
      expect(
        () => noEncoder.generateMessageJson(
          jsonEncode(message('image', blob: 'AQID')),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      noEncoder.dispose();
      final qwen = await client(input: model(family: 5));
      qwen.createConversation();
      expect(
        () => qwen.generateMessageJson(
          jsonEncode(message('image', blob: 'AQID')),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'missing visual setter refuses explicit budget but keeps plain image transport',
    () async {
      set('metadata_flags', 7, variants['visual']);
      final adapter = await client(lib: variants['visual']);
      adapter.createConversation();
      expect(adapter.resolveDefaultVisualTokenBudget(256), isNull);
      expect(
        () => adapter.generateMessageJson(
          jsonEncode(message('image', blob: 'AQID')),
          visualTokenBudget: 256,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'missing native modality proof refuses media before conversation allocation',
    () async {
      final adapter = await client(lib: variants['modality']);
      expect(
        () => adapter.createConversation(
          messages: [message('image', blob: 'AQID')],
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test('old C ABI is refused before allocation', () {
    expect(
      () => LiteRtLmV1RuntimeClient(variants['old']!),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(integer('live', variants['old']), 0);
  });

  for (final budget in [0, -1, 0x80000000]) {
    test('invalid visual budget $budget allocates no optional args', () async {
      final adapter = await client();
      adapter.createConversation();
      expect(
        () => adapter.generateMessageJson(
          jsonEncode(message('image', blob: 'AQID')),
          visualTokenBudget: budget,
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(integer('args_live'), 0);
    });
  }

  test(
    'visual setter failure captures status and frees optional args before send',
    () async {
      final adapter = await client();
      adapter.createConversation();
      set('fail', 85);
      expect(
        () => adapter.generateMessageJson(
          jsonEncode(message('image', blob: 'AQID')),
          visualTokenBudget: 256,
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'native status',
            contains('stage85'),
          ),
        ),
      );
      expect(integer('args_live'), 0);
      set('fail', 0);
      await complete(
        adapter.generateMessageJson(
          jsonEncode(message('image', blob: 'AQID')),
          visualTokenBudget: 256,
        ),
      );
    },
  );
  for (final mode in [1, 2]) {
    test(
      'legacy inferred Gemma route $mode uses exact native tokenizer fingerprint',
      () async {
        set('media_inference', mode);
        final file = File('${directory.path}/inferred${nextFile++}.litertlm')
          ..writeAsBytesSync(_bundle([(type: 5, data: _metadata(null))]));
        final adapter = await client(input: file);
        adapter.createConversation();
        expect(adapter.resolveDefaultVisualTokenBudget(256), isNull);
        await complete(
          adapter.generateMessageJson(
            jsonEncode(message('audio', blob: 'AQID')),
          ),
        );
      },
    );
  }
  test(
    'unknown, malformed and filename-only processor proof refuse media',
    () async {
      for (final metadata in [
        Uint8List.fromList([
          ..._metadata(null),
          ..._protoField(6, _protoField(14, [])),
        ]),
        Uint8List.fromList([
          ..._metadata(null),
          ..._protoField(6, [0x42, 9]),
        ]),
        _metadata(null),
      ]) {
        final file = File('${directory.path}/Gemma4-${nextFile++}.litertlm')
          ..writeAsBytesSync(_bundle([(type: 5, data: metadata)]));
        expect(
          readLiteRtLmBundleMediaProcessor(file.path)?.family,
          anyOf(isNull, 0),
        );
        final adapter = await client(input: file);
        adapter.createConversation();
        expect(adapter.resolveDefaultVisualTokenBudget(256), isNull);
        expect(
          () => adapter.generateMessageJson(
            jsonEncode(message('image', blob: 'AQID')),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        adapter.dispose();
      }
    },
  );
  test(
    'local encoded audio path and absent Gemma4 visual setter preserve plain media',
    () async {
      set('metadata_flags', 7, variants['visual']);
      final adapter = await client(lib: variants['visual']);
      adapter.createConversation();
      final file = File('${directory.path}/audio.wav')
        ..writeAsBytesSync([1, 2, 3]);
      await complete(
        adapter.generateMessageJson(
          jsonEncode(message('audio', path: file.path)),
        ),
        lib: variants['visual'],
      );
    },
  );
  test('strict media content shapes fail before native send', () async {
    final adapter = await client();
    adapter.createConversation();
    final invalid = <Map<String, dynamic>>[
      message('image', blob: '!'),
      message('audio', blob: ''),
      message('image', path: '/missing/media'),
      message('image', path: 'https://invalid.example/image'),
      message('image', path: 'bad\u0000path'),
      {
        'role': 'user',
        'content': [
          {'type': 'image', 'blob': 'AQID', 'path': '/missing'},
        ],
      },
    ];
    final unsupported = <Map<String, dynamic>>[
      message('image', blob: 'AQID', role: 'system'),
      message('audio', blob: 'AQID', role: 'tool'),
      {
        'role': 'user',
        'content': [
          {'type': 'image', 'blob': 'AQID', 'width': 1, 'height': 1},
        ],
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'audio',
            'samples': [0.1],
          },
        ],
      },
      {
        'role': 'user',
        'content': [
          {'type': 'video', 'path': '/video'},
        ],
      },
      {
        ...message('image', blob: 'AQID', role: 'assistant'),
        'reasoning_content': 'hidden',
      },
      {...message('image', blob: 'AQID'), 'tool_calls': []},
    ];
    final before = integer('sends');
    for (final value in invalid) {
      expect(
        () => adapter.generateMessageJson(jsonEncode(value)),
        throwsA(
          anyOf(
            isA<LlamaArgumentException>(),
            isA<LlamaUnsupportedException>(),
          ),
        ),
      );
    }
    for (final value in unsupported) {
      expect(
        () => adapter.generateMessageJson(jsonEncode(value)),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
    expect(integer('sends'), before);
  });
  test(
    'service preserves media across history expansion and active sends',
    () async {
      final input = model();
      final service = LiteRtLmService(
        runtimeClientFactory: () => LiteRtLmV1RuntimeClient(library),
        useTempCacheDir: false,
        linkParentDirectory: directory,
        readBundleChatTemplate: (_) => null,
        readBundleFirstChannel: (_) => null,
      );
      addTearDown(() async {
        if (service.nativeSettlement == LiteRtLmNativeSettlement.pending) {
          service.cancelGeneration();
          emit(null, finalChunk: true);
          final deadline = Stopwatch()..start();
          while (service.nativeSettlement == LiteRtLmNativeSettlement.pending) {
            if (deadline.elapsed > const Duration(seconds: 3)) {
              fail('fixture service did not settle');
            }
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        }
        service.dispose();
      });
      final params = ModelParams(
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        numberOfThreads: 2,
        contextSize: 64,
        liteRtLmCacheDir: '${directory.path}/cache',
      );
      final modelHandle = await service.loadModel(input.path, params);
      final context = service.createContext(modelHandle, params);
      final image1 = Uint8List.fromList([1, 2, 3]),
          image2 = Uint8List.fromList([4, 5, 6]);
      for (final expanded in [false, true]) {
        final history = [
          if (expanded)
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [LlamaImageContent(bytes: image1)],
            ),
          if (expanded)
            const LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: 'history answer',
            ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              const LlamaTextContent('describe'),
              LlamaImageContent(bytes: image2),
              LlamaAudioContent(bytes: Uint8List.fromList([7, 8, 9])),
            ],
          ),
        ];
        final before = integer('sends');
        final output = service
            .generateChat(
              context,
              history,
              const GenerationParams(maxTokens: 16, temp: 0, seed: 1),
              enableThinking: false,
            )
            .toList();
        await waitForSend(before);
        final active = jsonDecode(text('message')) as Map;
        expect(active['content'], [
          {'type': 'text', 'text': 'describe'},
          {'type': 'image', 'blob': base64Encode(image2)},
          {'type': 'audio', 'blob': 'BwgJ'},
        ]);
        if (expanded) {
          expect(jsonDecode(preface())[0]['content'], [
            {'type': 'image', 'blob': base64Encode(image1)},
          ]);
        }
        expect(integer('media_budget'), 280);
        expect(integer('media_hint_calls'), 0);
        emit(
          '{"role":"assistant","content":[{"type":"text","text":"fixture answer"}]}',
          finalChunk: true,
        );
        expect(
          utf8.decode((await output).expand((chunk) => chunk).toList()),
          'fixture answer',
        );
      }
    },
  );
  test(
    'history count validates before native allocation without promising capacity',
    () async {
      for (final count in [0, -1, 0x80000000]) {
        final adapter = LiteRtLmV1RuntimeClient(library);
        addTearDown(adapter.dispose);
        final before = integer('live');
        await expectLater(
          adapter.initialize(
            modelPath: model().path,
            backend: 'cpu',
            visionBackend: 'cpu',
            maxNumImages: count,
            speculativeDecoding: false,
          ),
          throwsA(isA<LlamaArgumentException>()),
        );
        expect(integer('live'), before);
      }
      final adapter = LiteRtLmV1RuntimeClient(library);
      addTearDown(adapter.dispose);
      await expectLater(
        adapter.initialize(
          modelPath: model().path,
          backend: 'cpu',
          maxNumImages: 2,
          speculativeDecoding: false,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(integer('media_hint_calls'), 0);
    },
  );
}
