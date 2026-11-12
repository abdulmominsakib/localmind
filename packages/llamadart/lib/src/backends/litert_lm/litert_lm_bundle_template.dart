import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _maxHeaderBytes = 16 * 1024 * 1024;
const int _maxMetadataBytes = 16 * 1024 * 1024;

// `AnySectionDataType.LlmMetadataProto` in LiteRT-LM's
// `schema/core/litertlm_header_schema.fbs`.
const int _llmMetadataSectionType = 5;

// `LlmMetadata.jinja_prompt_template` in `runtime/proto/llm_metadata.proto`.
const int _jinjaPromptTemplateField = 7;

// `LlmMetadata.channels` in `runtime/proto/llm_metadata.proto`.
const int _channelsField = 8;

/// A conversation template that renders the text of each message unchanged,
/// so a raw prompt sent as one user message reaches the model as it is,
/// instead of inside the bundle's chat turn.
///
/// It reads content both as a string and as a list of parts, the form
/// LiteRT-LM v0.18 and later pass. All of its literal whitespace sits inside
/// tags, so the runtime's block trimming cannot change the prompt.
const String liteRtLmRawPromptTemplate =
    '{%- for message in messages -%}'
    '{%- if message.content is string -%}'
    '{{ message.content }}'
    '{%- else -%}'
    '{%- for part in message.content -%}'
    "{%- if part.type == 'text' -%}{{ part.text }}{%- endif -%}"
    '{%- endfor -%}'
    '{%- endif -%}'
    '{%- endfor -%}';

/// The text of [liteRtLmContentShapeProbeMessage].
const String liteRtLmContentShapeProbeText = 'llamadart-content-shape-probe';

final RegExp _probeTextAsListItem = RegExp(
  '["\']text["\']\\s*:\\s*["\']$liteRtLmContentShapeProbeText["\']',
);

/// The message whose rendering shows whether a native LiteRT-LM conversation
/// template reads the content the runtime gives it. See
/// [liteRtLmRendersProbeText].
const Map<String, dynamic> liteRtLmContentShapeProbeMessage = {
  'role': 'user',
  'content': [
    {'type': 'text', 'text': liteRtLmContentShapeProbeText},
  ],
};

/// Whether [rendered], the prompt a native conversation rendered for
/// [liteRtLmContentShapeProbeMessage], holds the text of that message as text.
///
/// From LiteRT-LM v0.18 the runtime hands every template content as a list of
/// parts. A template that reads content as a string then loses the text or
/// writes the list, `[{"text": "...", "type": "text"}]`, into the prompt;
/// neither counts.
bool liteRtLmRendersProbeText(String rendered) => rendered
    .replaceAll(_probeTextAsListItem, '')
    .contains(liteRtLmContentShapeProbeText);

/// Returns [template] behind a prelude that gives it the content of a message
/// as a string when that content is a single text part, as LiteRT-LM runtimes
/// before v0.18 did for a template that reads content as a string.
///
/// Other content stays as the runtime passed it. The prelude rebinds
/// `messages`, so it does not reach a template that reads the message of a
/// turn from `message` (the runtime's `is_appending_to_prefill` form).
String liteRtLmTextContentAdapter(String template) =>
    '$_textContentAdapterPrelude$template';

// Ends with a block tag and a newline. The runtime trims the newline after a
// block tag, so [template] starts on a line of its own, where leading
// whitespace is handled as at the start of a template.
const String _textContentAdapterPrelude =
    '{%- set llamadart_adapter = namespace(messages=[]) -%}'
    '{%- for llamadart_message in messages -%}'
    '{%- set llamadart_content = llamadart_message.content -%}'
    '{%- if llamadart_content is sequence'
    ' and llamadart_content is not string'
    ' and llamadart_content | length == 1'
    ' and llamadart_content[0] is mapping'
    " and llamadart_content[0].type == 'text'"
    ' and llamadart_content[0].text is string -%}'
    '{%- set llamadart_adapter.messages = llamadart_adapter.messages'
    ' + [dict(llamadart_message, content=llamadart_content[0].text)] -%}'
    '{%- else -%}'
    '{%- set llamadart_adapter.messages = llamadart_adapter.messages'
    ' + [llamadart_message] -%}'
    '{%- endif -%}'
    '{%- endfor -%}'
    '{%- set messages = llamadart_adapter.messages %}\n';

/// The Jinja chat template embedded in the `.litertlm` bundle at [path], or
/// null when the file cannot be read, is not a bundle this reader understands
/// or declares no template.
///
/// The native runtime exposes no accessor for it.
String? readLiteRtLmBundleChatTemplate(String path) =>
    readLiteRtLmBundleMetadata(path)?.chatTemplate;

/// The embedded template and Qwen3 model-type declaration at [path].
///
/// Returns null under the same bounds and format constraints as
/// [readLiteRtLmBundleChatTemplate]. The model type is field 6 of
/// `LlmMetadata`, whose `LlmModelType` oneof uses field 5 for Qwen3 in
/// LiteRT-LM v0.18.0 (`runtime/proto/llm_model_type.proto`). A malformed
/// optional model type is ignored when the template is still readable.
({String? chatTemplate, bool isQwen3})? readLiteRtLmBundleMetadata(
  String path,
) {
  final metadata = _readLlmMetadata(path);
  if (metadata == null) {
    return null;
  }
  try {
    final fields = {
      for (final (field, value) in _protoFields(metadata)) field: value,
    };
    final template = fields[_jinjaPromptTemplateField];
    final modelType = fields[6];
    var isQwen3 = false;
    try {
      isQwen3 =
          modelType != null && _protoFields(modelType).lastOrNull?.$1 == 5;
    } on FormatException {
      // An invalid optional family declaration must not hide a usable template.
      if (template == null) return null;
    }
    return (
      chatTemplate: template == null ? null : utf8.decode(template),
      isQwen3: isQwen3,
    );
  } on FormatException {
    return null;
  }
}

/// Reads only the declared processor route used by C API 1.0 media admission.
/// A missing model type can use native tokenizer inference; malformed or future
/// oneof shapes return null rather than claiming a known processor.
({int family, bool genericImage, bool genericAudio})?
readLiteRtLmBundleMediaProcessor(String path) {
  final metadata = _readLlmMetadata(path);
  if (metadata == null) return null;
  try {
    final modelTypes = _protoFields(metadata).where((entry) => entry.$1 == 6);
    final modelType = modelTypes.lastOrNull?.$2;
    if (modelType == null) {
      return (family: 0, genericImage: false, genericAudio: false);
    }
    final entries = _protoFields(modelType).toList();
    const families = {1, 2, 3, 4, 5, 7, 8, 9, 11, 12, 13};
    if (entries.isEmpty ||
        entries.any((entry) => !families.contains(entry.$1))) {
      return null;
    }
    final (family, config) = entries.last;
    var image = false, audio = false;
    if (family == 1) {
      for (final (field, _, value) in _protoEntries(config)) {
        if (field == 3) {
          if (value != 0 && value != 1) return null;
          image = value == 1;
        }
        if (field == 4) {
          if (value != 0 && value != 1) return null;
          audio = value == 1;
        }
      }
    }
    return (family: family, genericImage: image, genericAudio: audio);
  } on FormatException {
    return null;
  }
}

/// The first response channel that the `.litertlm` bundle at [path]
/// declares, or null when it declares none or cannot be read.
///
/// LiteRT-LM v0.18 bounds a thinking token budget with the start and end
/// markers of this channel and applies no budget without one
/// (`Conversation::CreateDecodeConfig`). `isReasoning` is the channel's
/// optional `is_reasoning_channel` flag, null when the bundle omits it.
({String name, bool? isReasoning})? readLiteRtLmBundleFirstChannel(
  String path,
) {
  final channel = _readLiteRtLmFirstChannel(path, boundaries: false);
  return channel == null
      ? null
      : (name: channel.name, isReasoning: channel.isReasoning);
}

/// The first declared channel and its complete UTF-8 boundary strings.
/// Missing boundaries remain null; malformed/unknown boundary proof returns null.
/// This never substitutes a later reasoning channel for the native first one.
({String name, bool? isReasoning, String? start, String? end})?
readLiteRtLmBundleFirstChannelDetails(String path) =>
    _readLiteRtLmFirstChannel(path, boundaries: true);

({String name, bool? isReasoning, String? start, String? end})?
_readLiteRtLmFirstChannel(String path, {required bool boundaries}) {
  final metadata = _readLlmMetadata(path);
  if (metadata == null) return null;
  try {
    for (final (field, channel) in _protoFields(metadata)) {
      if (field != _channelsField) continue;
      String? name, start, end;
      bool? isReasoning;
      for (final (channelField, bytes, value) in _protoEntries(channel)) {
        if (channelField == 1 && bytes != null) {
          name = utf8.decode(bytes);
        } else if (boundaries && channelField == 2 && bytes != null) {
          start = utf8.decode(bytes);
        } else if (boundaries && channelField == 3 && bytes != null) {
          end = utf8.decode(bytes);
        } else if (channelField == 4 && value != null) {
          if (boundaries && value != 0 && value != 1) return null;
          isReasoning = value != 0;
        }
      }
      return name == null || name.isEmpty
          ? null
          : (name: name, isReasoning: isReasoning, start: start, end: end);
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// The serialized `LlmMetadata` section of the bundle at [path], or null when
/// the file cannot be read or is not a bundle this reader understands.
Uint8List? _readLlmMetadata(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final prefix = _read(file, 0, 32);
    if (ascii.decode(prefix.sublist(0, 8), allowInvalid: true) != 'LITERTLM') {
      return null;
    }
    final prefixData = ByteData.sublistView(prefix);
    final headerEnd = prefixData.getUint64(24, Endian.little);
    if (headerEnd <= 32 || headerEnd - 32 > _maxHeaderBytes) {
      return null;
    }
    final header = _FlatBuffer(_read(file, 32, headerEnd - 32));
    final sections = header.field(header.root, 1);
    final objects = sections == null
        ? null
        : header.field(header.indirect(sections), 0);
    if (objects == null) {
      return null;
    }
    for (final section in header.tables(objects)) {
      final type = header.field(section, 3);
      if (type == null || header.uint8(type) != _llmMetadataSectionType) {
        continue;
      }
      final begin = header.field(section, 1);
      final end = header.field(section, 2);
      if (begin == null || end == null) {
        return null;
      }
      final beginOffset = header.uint64(begin);
      final length = header.uint64(end) - beginOffset;
      if (length <= 0 || length > _maxMetadataBytes) {
        return null;
      }
      return _read(file, beginOffset, length);
    }
    return null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    file?.closeSync();
  }
}

Uint8List _read(RandomAccessFile file, int offset, int length) {
  file.setPositionSync(offset);
  final bytes = file.readSync(length);
  if (bytes.length != length) {
    throw const FormatException('Truncated LiteRT-LM bundle.');
  }
  return bytes;
}

Iterable<(int, Uint8List)> _protoFields(Uint8List metadata) sync* {
  for (final (field, bytes, _) in _protoEntries(metadata)) {
    if (bytes != null) yield (field, bytes);
  }
}

/// The fields of a serialized protobuf message: length-delimited ones with
/// their bytes, varint ones with their value.
Iterable<(int, Uint8List?, int?)> _protoEntries(Uint8List metadata) sync* {
  var offset = 0;

  int varint() {
    var value = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (offset >= metadata.length) {
        throw const FormatException('Truncated LiteRT-LM metadata.');
      }
      final byte = metadata[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) {
        return value;
      }
    }
    throw const FormatException('Malformed LiteRT-LM metadata.');
  }

  void skip(int length) {
    if (length < 0 || length > metadata.length - offset) {
      throw const FormatException('Truncated LiteRT-LM metadata.');
    }
    offset += length;
  }

  while (offset < metadata.length) {
    final key = varint();
    final field = key >> 3;
    switch (key & 0x7) {
      case 0:
        yield (field, null, varint());
      case 1:
        skip(8);
      case 2:
        final length = varint();
        final start = offset;
        skip(length);
        yield (field, Uint8List.sublistView(metadata, start, offset), null);
      case 5:
        skip(4);
      default:
        throw const FormatException('Malformed LiteRT-LM metadata.');
    }
  }
}

/// Bounds-checked reads of the FlatBuffers encoding of a bundle header.
class _FlatBuffer {
  _FlatBuffer(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  final ByteData _data;

  int get root => indirect(0);

  int uint8(int offset) => _data.getUint8(_checked(offset, 1));

  int uint64(int offset) => _data.getUint64(_checked(offset, 8), Endian.little);

  /// The position that the offset stored at [offset] points to.
  int indirect(int offset) =>
      offset + _data.getUint32(_checked(offset, 4), Endian.little);

  /// The position of field [index] of the table at [table], or null when the
  /// table omits it.
  int? field(int table, int index) {
    final vtable = table - _data.getInt32(_checked(table, 4), Endian.little);
    final slot = 4 + index * 2;
    if (slot + 2 > _data.getUint16(_checked(vtable, 2), Endian.little)) {
      return null;
    }
    final fieldOffset = _data.getUint16(
      _checked(vtable + slot, 2),
      Endian.little,
    );
    return fieldOffset == 0 ? null : table + fieldOffset;
  }

  /// The tables of the vector that the field at [vectorField] points to.
  Iterable<int> tables(int vectorField) sync* {
    final vector = indirect(vectorField);
    final count = _data.getUint32(_checked(vector, 4), Endian.little);
    for (var i = 0; i < count; i++) {
      yield indirect(vector + 4 + i * 4);
    }
  }

  int _checked(int offset, int length) {
    if (offset < 0 || offset > _data.lengthInBytes - length) {
      throw const FormatException('Malformed LiteRT-LM bundle header.');
    }
    return offset;
  }
}
