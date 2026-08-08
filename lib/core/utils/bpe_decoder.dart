import 'dart:convert';

class SimpleStringSink implements Sink<String> {
  final void Function(String) onAdd;
  SimpleStringSink(this.onAdd);
  
  @override
  void add(String data) => onAdd(data);
  
  @override
  void close() {}
}

/// A decoder that converts BPE-encoded unicode strings (used by Qwen/GPT-2 tokenizers)
/// back into standard UTF-8 strings. Supports streaming/chunked decoding.
class BpeDecoder {
  late final ByteConversionSink _utf8Sink;
  String _decoded = '';
  bool _hasError = false;

  BpeDecoder() {
    _utf8Sink = utf8.decoder.startChunkedConversion(
      SimpleStringSink((str) {
        _decoded += str;
      }),
    );
  }

  /// Decodes a chunk of a BPE-encoded unicode string and returns the newly decoded text segment.
  String decodeChunk(String bpeChunk) {
    if (bpeChunk.isEmpty) return '';
    if (_hasError) return bpeChunk;

    // Check if bpeChunk contains characters with code point > 255 that are NOT in _bpeToByte.
    // If so, the input is ALREADY a decoded standard string (e.g. Turkish 'İ' = 352).
    for (var i = 0; i < bpeChunk.length; i++) {
      final code = bpeChunk.codeUnitAt(i);
      if (code > 255 && !_bpeToByte.containsKey(code)) {
        return bpeChunk;
      }
    }

    final bytes = <int>[];
    for (var i = 0; i < bpeChunk.length; i++) {
      final code = bpeChunk.codeUnitAt(i);
      final byte = _bpeToByte[code] ?? code;
      if (byte >= 0 && byte <= 255) {
        bytes.add(byte);
      }
    }
    
    final previousLength = _decoded.length;
    try {
      _utf8Sink.add(bytes);
      return _decoded.substring(previousLength);
    } catch (_) {
      _hasError = true;
      return bpeChunk;
    }
  }

  /// Flushes any remaining bytes in the decoder buffer and returns the remaining decoded text.
  String flush() {
    if (_hasError) return '';
    final previousLength = _decoded.length;
    try {
      _utf8Sink.close();
      return _decoded.substring(previousLength);
    } catch (_) {
      return '';
    }
  }
}

const Map<int, int> _bpeToByte = {
  33: 33, 34: 34, 35: 35, 36: 36, 37: 37, 38: 38, 39: 39, 40: 40,
  41: 41, 42: 42, 43: 43, 44: 44, 45: 45, 46: 46, 47: 47, 48: 48,
  49: 49, 50: 50, 51: 51, 52: 52, 53: 53, 54: 54, 55: 55, 56: 56,
  57: 57, 58: 58, 59: 59, 60: 60, 61: 61, 62: 62, 63: 63, 64: 64,
  65: 65, 66: 66, 67: 67, 68: 68, 69: 69, 70: 70, 71: 71, 72: 72,
  73: 73, 74: 74, 75: 75, 76: 76, 77: 77, 78: 78, 79: 79, 80: 80,
  81: 81, 82: 82, 83: 83, 84: 84, 85: 85, 86: 86, 87: 87, 88: 88,
  90: 90, 91: 91, 92: 92, 93: 93, 94: 94, 95: 95, 96: 96, 97: 97,
  98: 98, 99: 99, 100: 100, 101: 101, 102: 102, 103: 103, 104: 104,
  105: 105, 106: 106, 107: 107, 108: 108, 109: 109, 110: 110,
  111: 111, 112: 112, 113: 113, 114: 114, 115: 115, 116: 116,
  117: 117, 118: 118, 119: 119, 120: 120, 121: 121, 122: 122,
  123: 123, 124: 124, 125: 125, 126: 126, 161: 161, 162: 162,
  163: 163, 164: 164, 165: 165, 166: 166, 167: 167, 168: 168,
  169: 169, 170: 170, 171: 171, 172: 172, 174: 174, 175: 175,
  176: 176, 177: 177, 178: 178, 179: 179, 180: 180, 181: 181,
  182: 182, 183: 183, 184: 184, 185: 185, 186: 186, 187: 187,
  188: 188, 189: 189, 190: 190, 191: 191, 192: 192, 193: 193,
  194: 194, 195: 195, 196: 196, 197: 197, 198: 198, 199: 199,
  200: 200, 201: 201, 202: 202, 203: 203, 204: 204, 205: 205,
  206: 206, 207: 207, 208: 208, 209: 209, 210: 210, 211: 211,
  212: 212, 213: 213, 214: 214, 215: 215, 216: 216, 217: 217,
  218: 218, 219: 219, 220: 220, 221: 221, 222: 222, 223: 223,
  224: 224, 225: 225, 226: 226, 227: 227, 228: 228, 229: 229,
  230: 230, 231: 231, 232: 232, 233: 233, 234: 234, 235: 235,
  236: 236, 237: 237, 238: 238, 239: 239, 240: 240, 241: 241,
  242: 242, 243: 243, 244: 244, 245: 245, 246: 246, 247: 247,
  248: 248, 249: 249, 250: 250, 251: 251, 252: 252, 253: 253,
  254: 255, 255: 255, 256: 0, 257: 1, 258: 2, 259: 3, 260: 4,
  261: 5, 262: 6, 263: 7, 264: 8, 265: 9, 266: 10, 267: 11, 268: 12,
  269: 13, 270: 14, 271: 15, 272: 16, 273: 17, 274: 18, 275: 19,
  276: 20, 277: 21, 278: 22, 279: 23, 280: 24, 281: 25, 282: 26,
  283: 27, 284: 28, 285: 29, 286: 30, 287: 31, 288: 32, 289: 127,
  290: 128, 291: 129, 292: 130, 293: 131, 294: 132, 295: 133,
  296: 134, 297: 135, 298: 136, 299: 137, 300: 138, 301: 139,
  302: 140, 303: 141, 304: 142, 305: 143, 306: 144, 307: 145,
  308: 146, 309: 147, 310: 148, 311: 149, 312: 150, 313: 151,
  314: 152, 315: 153, 316: 154, 317: 155, 318: 156, 319: 157,
  320: 158, 321: 159, 322: 160, 323: 173,
};
