import 'dart:async';
import 'dart:typed_data';

import 'package:genkit/plugin.dart' as genkit;
import 'package:http/http.dart' as http;

/// Resolves remote image or audio input into encoded bytes on native platforms.
///
/// Install this explicitly on the plugin. Local paths, file URLs, data URLs and
/// browser image URLs bypass it. Implementations own authentication, URL access
/// policy, transfer limits and cancellation; the plugin never caches results.
abstract interface class LlamaDartMediaResolver {
  /// Reads [uri] as the requested [contentType], observing [cancel].
  ///
  /// Return encoded image/audio bytes, not decoded pixels or PCM samples.
  /// [contentType] is an image or audio MIME type and may use a wildcard subtype.
  /// Exceptions are replaced with a sanitized Genkit error by the plugin.
  Future<Uint8List> resolve(
    Uri uri, {
    required String contentType,
    genkit.CancellationToken? cancel,
  });
}

/// Explicit, bounded HTTP(S) media resolution with an application-owned client.
///
/// [allowUri] checks the initial URL and every redirect before any request.
/// Supply the application's normal host/network policy; permitting every URL
/// is inappropriate when requests can contain untrusted URLs. The client can
/// supply authentication and must support [http.AbortableRequest]. It is never
/// closed by this resolver or the plugin. Authentication across redirects is
/// the client's responsibility; use a policy that limits trusted destinations.
///
/// Transfers stay in memory without temporary files or a persistent cache.
/// MIME headers must match the requested image/audio type. This checks the
/// transport declaration; the model runtime still validates codecs and bytes.
class HttpLlamaDartMediaResolver implements LlamaDartMediaResolver {
  /// Creates a resolver with required client ownership and URL policy.
  ///
  /// Defaults permit 20 MiB, 30 seconds for the entire transfer and three
  /// redirects. HTTPS-to-HTTP redirects and URL user credentials are rejected.
  /// Throws [ArgumentError] for nonpositive limits or negative [maxRedirects].
  HttpLlamaDartMediaResolver({
    required this.client,
    required this.allowUri,
    this.maxBytes = 20 * 1024 * 1024,
    this.timeout = const Duration(seconds: 30),
    this.maxRedirects = 3,
  }) {
    if (maxBytes <= 0 || timeout <= Duration.zero || maxRedirects < 0) {
      throw ArgumentError('Media transfer limits must be positive.');
    }
  }

  /// Application-owned client, including any authentication or proxy policy.
  final http.Client client;

  /// Policy evaluated before the initial request and each redirect.
  ///
  /// Reject untrusted destinations, including local/private hosts as required
  /// by your deployment. DNS resolution policy remains the client's concern.
  final bool Function(Uri uri) allowUri;

  /// Maximum encoded response size, checked against headers and streamed bytes.
  final int maxBytes;

  /// Total time budget, including redirects, headers and response streaming.
  final Duration timeout;

  /// Maximum redirects followed after policy validation.
  final int maxRedirects;

  /// Downloads encoded bytes with limits, MIME checking and request abortion.
  ///
  /// Failures use sanitized [genkit.GenkitException] messages; caller-provided
  /// cancellation reasons, URLs, headers and client exceptions are not exposed.
  /// Cancelling aborts the transfer without closing the caller-owned client.
  @override
  Future<Uint8List> resolve(
    Uri uri, {
    required String contentType,
    genkit.CancellationToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw genkit.CancelledException(token: cancel);
    }
    final abort = Completer<void>();
    final interrupted = Completer<Uint8List>();
    genkit.GenkitException? interruption;
    void interrupt(genkit.GenkitException error) {
      interruption = error;
      if (!interrupted.isCompleted) interrupted.completeError(error);
      if (!abort.isCompleted) abort.complete();
    }

    final unregister = cancel?.onCancel(
      () => interrupt(genkit.CancelledException(token: cancel)),
    );
    final timer = Timer(
      timeout,
      () => interrupt(
        _MediaError(
          'Remote media transfer exceeded its time limit.',
          status: genkit.StatusCode.deadlineExceeded,
        ),
      ),
    );
    try {
      return await Future.any([
        _download(uri, contentType.toLowerCase(), abort),
        interrupted.future,
      ]);
    } on _MediaError {
      rethrow;
    } on genkit.CancelledException {
      if (interruption != null) throw interruption!;
      throw genkit.CancelledException(token: cancel);
    } catch (_) {
      if (interruption != null) throw interruption!;
      throw genkit.GenkitException(
        'Remote media transfer failed. Check the client, authentication and URL policy.',
        status: genkit.StatusCode.invalidArgument,
      );
    } finally {
      timer.cancel();
      unregister?.call();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<Uint8List> _download(
    Uri uri,
    String requestedType,
    Completer<void> abort,
  ) async {
    if (!_isMediaType(requestedType)) {
      throw _invalid('Remote media requires an image/* or audio/* MIME type.');
    }
    for (var redirects = 0; ; redirects++) {
      if (abort.isCompleted) throw genkit.CancelledException();
      if ((uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !allowUri(uri)) {
        throw _invalid(
          'Remote media URL is not permitted by the application policy.',
        );
      }
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await client.send(request);
      if (abort.isCompleted) {
        await response.stream.listen((_) {}).cancel();
        throw genkit.CancelledException();
      }
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        if (redirects >= maxRedirects) {
          throw _invalid('Remote media exceeded its redirect limit.');
        }
        final location = response.headers['location'];
        final next = location == null ? null : Uri.tryParse(location);
        if (next == null) throw _invalid('Remote media redirect is invalid.');
        final target = uri.resolveUri(next);
        if (uri.scheme == 'https' && target.scheme == 'http') {
          throw _invalid('Remote media cannot redirect from HTTPS to HTTP.');
        }
        uri = target;
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw _invalid(
          'Remote media server did not return a successful response.',
        );
      }
      final actualType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final matches =
          actualType != null &&
          _isMediaType(actualType) &&
          !actualType.contains('*') &&
          (requestedType.endsWith('/*')
              ? actualType.startsWith('${requestedType.split('/').first}/')
              : actualType == requestedType);
      if (!matches || (response.contentLength ?? 0) > maxBytes) {
        await response.stream.listen((_) {}).cancel();
        throw _invalid(
          !matches
              ? 'Remote media response MIME type does not match the requested type.'
              : 'Remote media exceeded its encoded byte limit.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (abort.isCompleted) throw genkit.CancelledException();
        if (bytes.length + chunk.length > maxBytes) {
          throw _invalid('Remote media exceeded its encoded byte limit.');
        }
        bytes.add(chunk);
      }
      if (bytes.isEmpty) throw _invalid('Remote media response was empty.');
      return bytes.takeBytes();
    }
  }
}

bool _isMediaType(String type) =>
    RegExp(r'^(image|audio)/[a-z0-9!#$&^_.+*-]+$').hasMatch(type);

_MediaError _invalid(String message) =>
    _MediaError(message, status: genkit.StatusCode.invalidArgument);

class _MediaError extends genkit.GenkitException {
  _MediaError(super.message, {required super.status});
}
