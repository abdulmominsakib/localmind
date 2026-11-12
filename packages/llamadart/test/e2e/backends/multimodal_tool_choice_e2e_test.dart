@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// Qualifies `tool_choice: auto` for a request with a user image and tools
/// on a real vision model through native llama.cpp: the tool grammar stays
/// lazy, so the model can answer in text.
///
/// Set LLAMADART_MM_TOOLS_MODEL and LLAMADART_MM_TOOLS_MMPROJ to a GGUF
/// vision model and its projector, such as Qwen3.5-0.8B.
/// LLAMADART_MM_TOOLS_CHAT_TEMPLATE optionally names a template file used as
/// `ModelParams.chatTemplate`. LLAMADART_MM_TOOLS_BACKEND picks a
/// `GpuBackend` (default `cpu`).
void main() {
  final env = Platform.environment;
  final model = env['LLAMADART_MM_TOOLS_MODEL'];
  final mmproj = env['LLAMADART_MM_TOOLS_MMPROJ'];
  final templatePath = env['LLAMADART_MM_TOOLS_CHAT_TEMPLATE'];
  final backend = GpuBackend.values.byName(
    env['LLAMADART_MM_TOOLS_BACKEND'] ?? 'cpu',
  );
  late LlamaEngine engine;

  setUpAll(() async {
    expect(model, isNotNull, reason: 'Set LLAMADART_MM_TOOLS_MODEL');
    expect(mmproj, isNotNull, reason: 'Set LLAMADART_MM_TOOLS_MMPROJ');
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      model!,
      modelParams: ModelParams(
        contextSize: 4096,
        gpuLayers: backend == GpuBackend.cpu ? 0 : 99,
        preferredBackend: backend,
        chatTemplate: templatePath == null
            ? null
            : File(templatePath).readAsStringSync(),
      ),
    );
    await engine.loadMultimodalProjector(mmproj!);
  });

  tearDownAll(() => engine.dispose());

  test('a user image with tools is answered in text', () async {
    final reply = await engine.complete(
      [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(bytes: _solidPng(20, 40, 220)),
            const LlamaTextContent(
              'What is the main color of this image? Answer in one word.',
            ),
          ],
        ),
      ],
      tools: [
        ToolDefinition(
          name: 'take_photo',
          description: 'Take a new photo with the camera.',
          parameters: [],
        ),
      ],
      enableThinking: false,
      params: const GenerationParams(
        temp: 0,
        penalty: 1,
        seed: 1,
        maxTokens: 48,
      ),
    );
    stdout.writeln(
      jsonEncode({
        'text': reply.text,
        'tool_calls': [for (final call in reply.toolCalls) call.name],
        'finish': reply.finishReason?.name,
        'prompt_tokens': reply.usage?.promptTokens,
        'backend': backend.name,
      }),
    );

    expect(reply.toolCalls, isEmpty);
    expect(reply.text.toLowerCase(), contains('blue'));
  });
}

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
