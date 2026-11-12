@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dinja/dinja.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../../../support/litert_lm_content_templates.dart';

const _llmMetadata = 5;
const _tokenizer = 6;

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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'llamadart_litert_bundle_template_test_',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String write(List<int> bytes) {
    final file = File('${tempDir.path}/model.litertlm')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  group('Qwen3 bundle metadata', () {
    // LlmMetadata.llm_model_type is field 6; its Qwen3 oneof is field 5.
    // https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/runtime/proto/llm_model_type.proto
    for (final (name, modelType, expected) in <(String, List<int>?, bool)>[
      ('absent', null, false),
      ('empty', [], false),
      ('Qwen3', [0x2a, 0], true),
      ('generic', [0x0a, 0], false),
      ('Qwen2.5', [0x3a, 0], false),
      ('future family', [0x72, 0], false),
      ('Qwen3 replaced by generic', [0x2a, 0, 0x0a, 0], false),
      ('generic replaced by Qwen3', [0x0a, 0, 0x2a, 0], true),
      ('nested Qwen3 field in generic config', [0x0a, 2, 0x2a, 0], false),
    ]) {
      test(name, () {
        const template = '{{ messages }}';
        final metadata = Uint8List.fromList([
          ..._metadata(template),
          if (modelType != null) ..._protoField(6, modelType),
        ]);
        final path = write(_bundle([(type: _llmMetadata, data: metadata)]));
        expect(readLiteRtLmBundleMetadata(path), (
          chatTemplate: template,
          isQwen3: expected,
        ));
        expect(readLiteRtLmBundleChatTemplate(path), template);
      });
    }

    for (final badType in [
      [0x2a, 0x7f],
      [0x80],
      [0x2f],
    ]) {
      test('retains template with malformed model type $badType', () {
        const template = '{{ messages[0].content }}';
        final path = write(
          _bundle([
            (
              type: _llmMetadata,
              data: Uint8List.fromList([
                ..._metadata(template),
                ..._protoField(6, badType),
              ]),
            ),
          ]),
        );
        expect(readLiteRtLmBundleChatTemplate(path), template);
        expect(readLiteRtLmBundleMetadata(path)?.isQwen3, isNot(true));
      });
    }

    test('malformed model type is not classified', () {
      final path = write(
        _bundle([
          (type: _llmMetadata, data: _protoField(6, [0x2a, 0x7f])),
        ]),
      );
      expect(readLiteRtLmBundleMetadata(path), isNull);
    });
  });

  group('readLiteRtLmBundleFirstChannel', () {
    // LlmMetadata.channels is field 8; Channel holds channel_name (1), start
    // (2), end (3) and the optional is_reasoning_channel varint (4).
    // https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/runtime/proto/llm_metadata.proto
    Uint8List channel(String name, {bool? reasoning}) => _protoField(8, [
      ..._protoField(1, utf8.encode(name)),
      ..._protoField(2, utf8.encode('<|channel>$name')),
      ..._protoField(3, utf8.encode('<channel|>')),
      if (reasoning != null) ...[0x20, reasoning ? 1 : 0],
    ]);

    String bundleWith(List<int> channels) => write(
      _bundle([
        (
          type: _llmMetadata,
          data: Uint8List.fromList([
            ..._metadata('{{ messages }}'),
            ...channels,
          ]),
        ),
      ]),
    );

    test('reads the first declared channel', () {
      final path = bundleWith([
        ...channel('thought'),
        ...channel('tool', reasoning: false),
      ]);

      expect(readLiteRtLmBundleFirstChannel(path), (
        name: 'thought',
        isReasoning: null,
      ));
      expect(readLiteRtLmBundleChatTemplate(path), '{{ messages }}');
    });

    test('reads the reasoning flag', () {
      expect(
        readLiteRtLmBundleFirstChannel(
          bundleWith(channel('analysis', reasoning: true)),
        ),
        (name: 'analysis', isReasoning: true),
      );
      expect(
        readLiteRtLmBundleFirstChannel(
          bundleWith(channel('thought', reasoning: false)),
        ),
        (name: 'thought', isReasoning: false),
      );
    });

    test('is null without a named channel or readable metadata', () {
      expect(readLiteRtLmBundleFirstChannel(bundleWith(const [])), isNull);
      expect(readLiteRtLmBundleFirstChannel(bundleWith(channel(''))), isNull);
      expect(
        readLiteRtLmBundleFirstChannel(
          bundleWith(_protoField(8, [0x0a, 0x7f])),
        ),
        isNull,
      );
      expect(
        readLiteRtLmBundleFirstChannel(write(utf8.encode('not a bundle'))),
        isNull,
      );
    });
  });

  group('readLiteRtLmBundleChatTemplate', () {
    test('reads the template of the LlmMetadata section', () {
      const template = '{{ messages[0].content }} 안녕';
      final path = write(
        _bundle([
          (type: _tokenizer, data: Uint8List.fromList([1, 2, 3])),
          (type: _llmMetadata, data: _metadata(template)),
        ]),
      );

      expect(readLiteRtLmBundleChatTemplate(path), template);
    });

    test('is null for a bundle that declares no template', () {
      expect(
        readLiteRtLmBundleChatTemplate(
          write(_bundle([(type: _llmMetadata, data: _metadata(null))])),
        ),
        isNull,
      );
      expect(
        readLiteRtLmBundleChatTemplate(
          write(
            _bundle([
              (type: _tokenizer, data: Uint8List.fromList([1, 2, 3])),
            ]),
          ),
        ),
        isNull,
      );
    });

    test('reads no header or metadata above its size bound', () {
      const template = '{{ messages[0].content }}';
      const bound = 16 * 1024 * 1024;
      // The header of a bundle with one section is 84 bytes without padding.
      const headerAtBound = bound - 84;
      final metadata = _metadata(template);
      Uint8List metadataOf(int length) =>
          // An unknown length-delimited field after the template.
          (BytesBuilder()
                ..add(metadata)
                ..add([0x7a, ..._varint(length - metadata.length - 5)])
                ..add(Uint8List(length - metadata.length - 5)))
              .takeBytes();
      String? read(Uint8List data, {int headerPadding = 0}) =>
          readLiteRtLmBundleChatTemplate(
            write(
              _bundle([
                (type: _llmMetadata, data: data),
              ], headerPadding: headerPadding),
            ),
          );

      expect(read(metadata, headerPadding: headerAtBound), template);
      expect(read(metadata, headerPadding: headerAtBound + 1), isNull);
      expect(metadataOf(bound), hasLength(bound));
      expect(read(metadataOf(bound)), template);
      expect(read(metadataOf(bound + 1)), isNull);
    });

    test('is null for a truncated or malformed bundle', () {
      final bundle = _bundle([
        (type: _llmMetadata, data: _metadata('{{ messages }}')),
      ]);
      Uint8List patched(void Function(ByteData data) patch) {
        final copy = Uint8List.fromList(bundle);
        patch(ByteData.sublistView(copy));
        return copy;
      }

      // The only section object: its table starts 60 bytes into the header.
      const beginOffset = 32 + 60 + 8;
      const endOffset = 32 + 60 + 16;
      final begin = ByteData.sublistView(
        bundle,
      ).getUint64(beginOffset, Endian.little);

      for (final (name, bytes) in <(String, List<int>)>[
        ('truncated metadata', bundle.sublist(0, bundle.length - 4)),
        ('truncated header', bundle.sublist(0, 48)),
        ('truncated prefix', bundle.sublist(0, 16)),
        ('another magic', patched((data) => data.setUint8(0, 0x4d))),
        (
          'a header that ends inside the prefix',
          patched((data) => data.setUint64(24, 16, Endian.little)),
        ),
        (
          'a header above the size bound',
          patched((data) => data.setUint64(24, 1 << 40, Endian.little)),
        ),
        (
          'a table outside the header',
          patched((data) => data.setInt32(32 + 12, 1 << 20, Endian.little)),
        ),
        (
          'metadata above the size bound',
          patched(
            (data) =>
                data.setUint64(endOffset, begin + (1 << 40), Endian.little),
          ),
        ),
        (
          'metadata that ends before it begins',
          patched(
            (data) => data.setUint64(endOffset, begin - 1, Endian.little),
          ),
        ),
        (
          'metadata at a negative offset',
          patched((data) {
            data.setInt64(beginOffset, -4096, Endian.little);
            data.setInt64(endOffset, -4000, Endian.little);
          }),
        ),
        (
          'malformed metadata',
          _bundle([
            (type: _llmMetadata, data: Uint8List.fromList([0x3a, 0x7f, 0x41])),
          ]),
        ),
        ('another file', utf8.encode('fake model')),
      ]) {
        expect(
          readLiteRtLmBundleChatTemplate(write(bytes)),
          isNull,
          reason: name,
        );
      }
      expect(
        readLiteRtLmBundleChatTemplate('${tempDir.path}/missing.litertlm'),
        isNull,
      );
    });
  });

  group('liteRtLmRendersProbeText', () {
    const text = liteRtLmContentShapeProbeText;

    test('accepts the text itself', () {
      expect(
        liteRtLmRendersProbeText(
          '<|im_start|>user\n$text<|im_end|>\n<|im_start|>assistant\n',
        ),
        isTrue,
      );
    });

    test('rejects a serialized text part in either key order', () {
      for (final rendered in [
        '<|im_start|>user\n[{"text": "$text", "type": "text"}]<|im_end|>',
        '<|im_start|>user\n[{"type": "text", "text": "$text"}]<|im_end|>',
        "[{'type': 'text', 'text': '$text'}]",
      ]) {
        expect(liteRtLmRendersProbeText(rendered), isFalse);
      }
    });

    test('rejects a prompt without the text', () {
      expect(liteRtLmRendersProbeText(''), isFalse);
      expect(
        liteRtLmRendersProbeText('<|im_start|>user\n<|im_end|>\n'),
        isFalse,
      );
    });
  });

  group('liteRtLmRawPromptTemplate', () {
    const prompts = [
      'hi',
      '\n  The capital of France is',
      '<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n',
      '{{ messages }} {% if x %}literal{% endif %}\n\n',
      '안녕 \t trailing whitespace  \n',
    ];

    for (final prompt in prompts) {
      test('renders ${jsonEncode(prompt)} unchanged', () {
        expect(
          renderLiteRtLmContent(liteRtLmRawPromptTemplate, [
            {'type': 'text', 'text': prompt},
          ]),
          prompt,
        );
        expect(
          renderLiteRtLmContent(liteRtLmRawPromptTemplate, prompt),
          prompt,
        );
      });
    }

    test('renders only the text parts of a message', () {
      expect(
        renderLiteRtLmContent(liteRtLmRawPromptTemplate, [
          {'type': 'text', 'text': 'a'},
          {'type': 'image'},
          {'type': 'text', 'text': 'b'},
        ]),
        'ab',
      );
    });
  });

  group('liteRtLmTextContentAdapter', () {
    const probeParts = [
      {'type': 'text', 'text': liteRtLmContentShapeProbeText},
    ];

    bool rendersProbeText(String template) {
      try {
        return liteRtLmRendersProbeText(
          renderLiteRtLmContent(template, probeParts),
        );
      } on LlamaModelException {
        return false;
      }
    }

    for (final MapEntry(key: shape, value: template)
        in liteRtLmStringContentTemplates.entries) {
      final adapted = liteRtLmTextContentAdapter(template);

      test('gives a template $shape content the text of one text part', () {
        expect(rendersProbeText(template), isFalse);
        expect(rendersProbeText(adapted), isTrue);
        expect(
          renderLiteRtLmContent(adapted, const [
            {'type': 'text', 'text': 'Hello "there"'},
          ]),
          '<|im_start|>\nHello "there"<|im_end|>\n',
        );
        expect(
          renderLiteRtLmContent(adapted, 'Hello "there"'),
          renderLiteRtLmContent(template, 'Hello "there"'),
        );
      });
    }

    test('leaves a template that reads content parts as it renders', () {
      final adapted = liteRtLmTextContentAdapter(liteRtLmPartsContentTemplate);
      for (final content in <Object?>[
        probeParts,
        'Hello',
        const [
          {'type': 'text', 'text': 'one'},
          {'type': 'text', 'text': 'two'},
        ],
      ]) {
        expect(
          renderLiteRtLmContent(adapted, content),
          renderLiteRtLmContent(liteRtLmPartsContentTemplate, content),
        );
      }
      expect(rendersProbeText(liteRtLmPartsContentTemplate), isTrue);
    });

    test('leaves content that is not one text part as the runtime passed '
        'it', () {
      final template = liteRtLmStringContentTemplates['interpolating']!;
      final adapted = liteRtLmTextContentAdapter(template);
      for (final content in <Object?>[
        const [
          {'type': 'text', 'text': 'one'},
          {'type': 'text', 'text': 'two'},
        ],
        const [
          {'type': 'tool_response', 'name': 'weather', 'text': 'sunny'},
        ],
        const [
          {'type': 'image'},
        ],
        const [
          {'type': 'text', 'text': 123},
        ],
        const [
          {'type': 'text'},
        ],
        const [
          {'text': 'untyped'},
        ],
        const ['bare'],
        const <Object?>[],
      ]) {
        expect(
          renderLiteRtLmContent(adapted, content),
          renderLiteRtLmContent(template, content),
          reason: '$content',
        );
      }
      const withoutContent = {
        'messages': [
          {'role': 'assistant'},
        ],
      };
      expect(
        Template(adapted).render(withoutContent),
        Template(template).render(withoutContent),
      );
    });

    test('keeps how a template handles the whitespace it starts with', () {
      for (final template in [
        '\n  start',
        '  start',
        '  {% if true %}X{% endif %}',
        '  {%- if true %}X{% endif %}',
        "  {{ 'X' }}",
        '\n{% if true %}\nX{% endif %}',
      ]) {
        expect(
          Template(
            liteRtLmTextContentAdapter(template),
          ).render({'messages': const <Object?>[]}),
          Template(template).render({'messages': const <Object?>[]}),
          reason: template,
        );
      }
    });
  });
}
