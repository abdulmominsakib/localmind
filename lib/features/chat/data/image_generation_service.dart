import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;

enum ImageGenerationFailure implements Exception {
  unavailable,
  auth,
  quota,
  rejected,
  timeout,
  invalid,
  failed,
  saveFailed;

  String get code => 'image_generation_$name';

  static ImageGenerationFailure? fromCode(String? code) =>
      values.where((failure) => failure.code == code).firstOrNull;
}

class GeneratedImage {
  const GeneratedImage(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}

class ImageGenerationService {
  ImageGenerationService(
    this._dio, {
    this.timeout = const Duration(minutes: 3),
  });

  static const _maxImageBytes = 20 * 1024 * 1024;
  static const _maxJsonBytes = (_maxImageBytes * 4 ~/ 3) + 64 * 1024;
  static const _maxPixels = 24 * 1024 * 1024;
  final Dio _dio;
  final Duration timeout;

  Future<GeneratedImage> generate({
    required Uri endpoint,
    required Map<String, String> authHeaders,
    required bool allowsUrlResults,
    required String modelId,
    required String prompt,
    required CancelToken cancelToken,
  }) async {
    final timer = Timer(timeout, () {
      cancelToken.cancel(ImageGenerationFailure.timeout);
    });
    try {
      final response = await _dio.postUri<ResponseBody>(
        endpoint,
        data: {'model': modelId, 'prompt': prompt, 'n': 1},
        options: _options(headers: authHeaders),
        cancelToken: cancelToken,
      );
      final responseBytes = await _read(response, _maxJsonBytes);
      final payload = await compute(_decode, (responseBytes, allowsUrlResults));
      final bytes =
          payload.bytes ?? await _download(endpoint, payload.url!, cancelToken);
      final image = await _validate(bytes);
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      return image;
    } on DioException catch (error) {
      if (error.error == ImageGenerationFailure.timeout ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw ImageGenerationFailure.timeout;
      }
      if (CancelToken.isCancel(error)) rethrow;
      throw switch (error.response?.statusCode) {
        401 || 403 => ImageGenerationFailure.auth,
        402 || 429 => ImageGenerationFailure.quota,
        404 || 405 || 501 => ImageGenerationFailure.unavailable,
        400 || 422 => ImageGenerationFailure.rejected,
        _ => ImageGenerationFailure.failed,
      };
    } on FormatException {
      throw ImageGenerationFailure.invalid;
    } finally {
      timer.cancel();
    }
  }

  static ({Uint8List? bytes, String? url}) _decode((Uint8List, bool) input) {
    final (responseBytes, allowsUrlResults) = input;
    final json = jsonDecode(utf8.decode(responseBytes));
    final data = json is Map ? json['data'] : null;
    final first = data is List ? data.firstOrNull : null;
    if (first is! Map) throw ImageGenerationFailure.invalid;
    final base64 = first['b64_json'];
    if (base64 is String && base64.isNotEmpty) {
      if (base64.length > (_maxImageBytes * 4 ~/ 3) + 4) {
        throw ImageGenerationFailure.invalid;
      }
      return (bytes: base64Decode(base64), url: null as String?);
    }
    final url = first['url'];
    if (allowsUrlResults && url is String && url.isNotEmpty) {
      return (bytes: null as Uint8List?, url: url);
    }
    throw ImageGenerationFailure.invalid;
  }

  // This client has no redirect interceptor. Never replay the request or send
  // the API key to a provider-supplied image URL.
  Options _options({Map<String, String>? headers}) => Options(
    headers: headers,
    responseType: ResponseType.stream,
    receiveDataWhenStatusError: false,
    followRedirects: false,
  );

  Future<Uint8List> _download(
    Uri endpoint,
    String url,
    CancelToken cancelToken,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' &&
            (uri.scheme != 'http' || uri.origin != endpoint.origin))) {
      throw ImageGenerationFailure.invalid;
    }
    final response = await _dio.getUri<ResponseBody>(
      uri,
      options: _options(),
      cancelToken: cancelToken,
    );
    return _read(response, _maxImageBytes);
  }

  Future<Uint8List> _read(Response<ResponseBody> response, int limit) async {
    final body = response.data;
    if (body == null) throw ImageGenerationFailure.invalid;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > limit) {
        throw ImageGenerationFailure.invalid;
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<GeneratedImage> _validate(Uint8List bytes) async {
    if (bytes.length < 12 || bytes.length > _maxImageBytes) {
      throw ImageGenerationFailure.invalid;
    }
    final header = ByteData.sublistView(bytes);
    final extension = switch (header.getUint32(0)) {
      0x89504e47 when header.getUint32(4) == 0x0d0a1a0a => 'png',
      0x52494646 when header.getUint32(8) == 0x57454250 => 'webp',
      _ when header.getUint16(0) == 0xffd8 && bytes[2] == 0xff => 'jpg',
      _ => throw ImageGenerationFailure.invalid,
    };
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > _maxPixels ||
            descriptor.width > 8192 ||
            descriptor.height > 8192) {
          throw ImageGenerationFailure.invalid;
        }
        final codec = await descriptor.instantiateCodec(
          targetWidth: descriptor.width > 256 ? 256 : descriptor.width,
        );
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } catch (_) {
      throw ImageGenerationFailure.invalid;
    } finally {
      buffer.dispose();
    }
    return GeneratedImage(bytes, extension);
  }
}
