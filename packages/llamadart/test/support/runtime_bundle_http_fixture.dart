import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Serves hook downloads from in-memory [responses] keyed by URL.
///
/// Any other URL answers 404, which the hook does not retry, so a test can
/// never fall through to the network. Every requested URL is appended to
/// [requests].
final class RuntimeBundleHttpFixture {
  /// Creates a fixture serving [responses], where each [unreachable] URL
  /// fails like an offline request.
  RuntimeBundleHttpFixture(this.responses, {this.unreachable = const {}})
    : offline = false;

  /// Creates a fixture that fails every request without a response, like a
  /// build without network access.
  ///
  /// The failure is not one the hook retries, so a test never waits out the
  /// retry delays or reaches the curl fallback.
  RuntimeBundleHttpFixture.offline()
    : responses = const {},
      unreachable = const {},
      offline = true;

  /// Response bodies keyed by URL.
  final Map<String, List<int>> responses;

  /// Whether every request fails with [OfflineFixtureException].
  final bool offline;

  /// URLs that fail with [OfflineFixtureException].
  final Set<String> unreachable;

  /// URLs the hook requested, in order.
  final List<String> requests = [];

  /// A client factory for `withRuntimeBundleHttpClientForTesting`.
  http.Client createClient() => MockClient((request) async {
    final url = request.url.toString();
    requests.add(url);
    if (offline || unreachable.contains(url)) {
      throw OfflineFixtureException(url);
    }
    final body = responses[url];
    if (body == null) {
      return http.Response('not found', 404);
    }
    return http.Response.bytes(body, 200);
  });
}

/// The failure an offline [RuntimeBundleHttpFixture] raises for [url].
final class OfflineFixtureException implements Exception {
  /// Creates the failure for [url].
  const OfflineFixtureException(this.url);

  /// The URL that could not be reached.
  final String url;

  @override
  String toString() => 'OfflineFixtureException: $url is unreachable';
}

/// A `SHA256SUMS` body listing the SHA-256 of each archive in [archives].
String sha256SumsFor(Map<String, List<int>> archives) => [
  for (final MapEntry(key: name, value: bytes) in archives.entries)
    '${sha256.convert(bytes)}  $name',
  '',
].join('\n');
