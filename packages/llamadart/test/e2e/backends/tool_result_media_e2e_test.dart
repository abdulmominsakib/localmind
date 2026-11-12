@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// Qualifies image tool results on a real vision model: an image a tool
/// returns reaches the model's next turn through native llama.cpp.
///
/// Set LLAMADART_TOOL_MEDIA_MODEL and LLAMADART_TOOL_MEDIA_MMPROJ to a
/// Qwen3-VL GGUF and its projector. LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE
/// optionally names a template file used as `ModelParams.chatTemplate`, for
/// a closest-family model run with the Qwen3-VL template.
/// LLAMADART_TOOL_MEDIA_BACKEND picks a `GpuBackend` (default `cpu`).
void main() {
  final env = Platform.environment;
  final model = env['LLAMADART_TOOL_MEDIA_MODEL'];
  final mmproj = env['LLAMADART_TOOL_MEDIA_MMPROJ'];
  final templatePath = env['LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE'];
  final backend = GpuBackend.values.byName(
    env['LLAMADART_TOOL_MEDIA_BACKEND'] ?? 'cpu',
  );
  final photos = {
    'red': _solidPng(220, 20, 20),
    'blue': _solidPng(20, 40, 220),
  };
  late LlamaEngine engine;

  setUpAll(() async {
    expect(model, isNotNull, reason: 'Set LLAMADART_TOOL_MEDIA_MODEL');
    expect(mmproj, isNotNull, reason: 'Set LLAMADART_TOOL_MEDIA_MMPROJ');
    final template = templatePath == null
        ? null
        : File(templatePath).readAsStringSync();
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      model!,
      modelParams: ModelParams(
        contextSize: 4096,
        gpuLayers: backend == GpuBackend.cpu ? 0 : 99,
        preferredBackend: backend,
        chatTemplate: template,
      ),
    );
    await engine.loadMultimodalProjector(mmproj!);
    stdout.writeln(
      jsonEncode({
        'model_sha256': await _sha256(model),
        'mmproj_sha256': await _sha256(mmproj),
        if (template != null)
          'chat_template_sha256': '${sha256.convert(utf8.encode(template))}',
        'backend': backend.name,
        'os': Platform.operatingSystemVersion,
      }),
    );
  });

  tearDownAll(() => engine.dispose());

  test('capabilities report image tool results', () async {
    expect((await engine.capabilities).toolResultMedia, {
      LlamaToolResultMedia.image,
    });
  });

  for (final color in photos.keys) {
    test('the model reads a $color photo from a tool result', () async {
      // No tools in this request: the model answers from the tool turn
      // instead of calling the tool again.
      final reply = await engine.complete(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text:
                'Take a photo, then tell me the main color of the photo in '
                'one word.',
          ),
          const LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaToolCallContent(
                id: 'call_0',
                name: 'take_photo',
                arguments: {},
                rawJson: '{}',
              ),
            ],
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: 'call_0',
                name: 'take_photo',
                result: const {'ok': true},
                content: [LlamaImageContent(bytes: photos[color])],
              ),
            ],
          ),
        ],
        params: const GenerationParams(
          temp: 0,
          penalty: 1,
          seed: 1,
          maxTokens: 48,
        ),
      );
      stdout.writeln(
        jsonEncode({
          'case': 'history-$color',
          'text': reply.text,
          'thinking': reply.thinking,
          'finish': reply.finishReason?.name,
          'usage': reply.usage?.promptTokens,
        }),
      );
      expect(reply.text.toLowerCase(), contains(color));
    });
  }

  for (final color in ['red', 'blue']) {
    test('a handler output reaches the next model turn ($color)', () async {
      final session = ChatSession(engine);
      var calls = 0;
      final result = await session.sendWithTools(
        'Take one photo with the take_photo tool. When the photo comes back, '
        'do not call any tool again: answer with the main color of the photo '
        'in one word.',
        tools: [
          _camera((params) async {
            calls += 1;
            return LlamaToolOutput(
              output: const {'ok': true},
              content: [LlamaImageContent(bytes: photos[color])],
            );
          }),
        ],
        toolChoice: ToolChoice.required,
        params: const GenerationParams(
          temp: 0,
          penalty: 1,
          seed: 1,
          maxTokens: 96,
        ),
      );
      stdout.writeln(
        jsonEncode({
          'case': 'tool-loop-$color',
          'calls': calls,
          'rounds': result.rounds,
          'stop': result.stopReason.name,
          'text': result.completion.text,
        }),
      );
      expect(calls, greaterThanOrEqualTo(1));
      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      expect(result.completion.text.toLowerCase(), contains(color));
    });
  }
}

ToolDefinition _camera(ToolHandler? handler) => ToolDefinition(
  name: 'take_photo',
  description: 'Takes a photo with the camera and returns it.',
  parameters: const [],
  handler: handler,
);

Future<String> _sha256(String path) async =>
    '${await sha256.bind(File(path).openRead()).first}';

/// A 128x128 RGB PNG of one color.
Uint8List _solidPng(int r, int g, int b) {
  const size = 128;
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0);
    for (var x = 0; x < size; x++) {
      raw.add([r, g, b]);
    }
  }
  Uint8List chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    return (BytesBuilder()
          ..add(_uint32(data.length))
          ..add(body)
          ..add(_uint32(_crc32(body))))
        .toBytes();
  }

  return (BytesBuilder()
        ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(
          chunk('IHDR', [..._uint32(size), ..._uint32(size), 8, 2, 0, 0, 0]),
        )
        ..add(chunk('IDAT', ZLibEncoder().convert(raw.toBytes())))
        ..add(chunk('IEND', const [])))
      .toBytes();
}

List<int> _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
