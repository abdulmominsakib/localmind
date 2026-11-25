import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'web_page_fetcher.dart';
import 'web_search_client.dart';

/// API keys for search providers, kept in the platform keychain rather than
/// in settings (which are backed up and exported).
class WebSearchKeyStore {
  WebSearchKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(WebSearchProviderKind kind) =>
      'webSearchApiKey_${kind.name}';

  Future<String?> read(WebSearchProviderKind kind) async {
    final value = (await _storage.read(key: _key(kind)))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> write(WebSearchProviderKind kind, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _storage.delete(key: _key(kind));
    } else {
      await _storage.write(key: _key(kind), value: trimmed);
    }
  }
}

/// Built-in web search: one configured provider plus a page reader.
class WebSearchService {
  WebSearchService({
    required this.kind,
    required this.searxngUrl,
    required this._keyStore,
    Dio? dio,
    this._fetcher,
    this._client,
  }) : _dio = dio ?? Dio(_options);

  static final _options = BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  );

  final WebSearchProviderKind kind;
  final String searxngUrl;
  final WebSearchKeyStore _keyStore;
  final Dio _dio;
  WebPageFetcher? _fetcher;
  WebSearchClient? _client;

  WebPageFetcher get fetcher => _fetcher ??= WebPageFetcher(dio: _dio);

  /// Whether a search could be sent: a URL for SearXNG, a key otherwise.
  Future<bool> isConfigured() async {
    if (_client != null) return true;
    if (!kind.needsApiKey) return searxngUrl.trim().isNotEmpty;
    return await _keyStore.read(kind) != null;
  }

  Future<WebSearchClient> _resolveClient() async {
    final existing = _client;
    if (existing != null) return existing;
    final WebSearchClient client;
    switch (kind) {
      case WebSearchProviderKind.searxng:
        client = SearxngSearchClient(searxngUrl, dio: _dio);
      case WebSearchProviderKind.brave:
      case WebSearchProviderKind.tavily:
        final key = await _keyStore.read(kind);
        if (key == null) {
          throw WebSearchException(
            'No API key is set for ${providerLabel(kind)}.',
          );
        }
        client = kind == WebSearchProviderKind.brave
            ? BraveSearchClient(key, dio: _dio)
            : TavilySearchClient(key, dio: _dio);
    }
    return _client = client;
  }

  Future<List<WebSearchResult>> search(String query, {int count = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const WebSearchException('The search query is empty.');
    }
    final client = await _resolveClient();
    return client.search(
      trimmed.length > 300 ? trimmed.substring(0, 300) : trimmed,
      count: count.clamp(1, 10),
    );
  }

  Future<WebPage> fetch(String url, {int maxChars = 6000}) =>
      fetcher.fetch(url, maxChars: maxChars);

  /// Search results, plus the text of the first few pages, written for a
  /// model's system prompt.
  Future<String> buildContext(
    String query, {
    int results = 5,
    int pagesToRead = 2,
    int charsPerPage = 2500,
    DateTime? now,
  }) async {
    final date = (now ?? DateTime.now()).toIso8601String().split('T').first;
    final header =
        'Web search results for the user\'s latest message (searched on '
        '$date). Answer from them, cite sources inline as [1], [2], and end '
        'with a short "Sources" list of the links you used. If they don\'t '
        'answer the question, say so.';
    final List<WebSearchResult> found;
    try {
      found = await search(query, count: results);
    } on WebSearchException catch (e) {
      return 'A web search was requested but failed: ${e.message} '
          'Tell the user the search did not work.';
    }
    if (found.isEmpty) {
      return 'A web search for the user\'s message found no results. '
          'Tell the user nothing was found.';
    }

    final pages = await Future.wait([
      for (final result in found.take(pagesToRead))
        fetch(
          result.url,
          maxChars: charsPerPage,
        ).then<WebPage?>((page) => page).catchError((_) => null),
    ]);

    final buffer = StringBuffer(header);
    for (var i = 0; i < found.length; i++) {
      final result = found[i];
      buffer
        ..write('\n\n[${i + 1}] ${result.title}\n')
        ..write(result.url);
      if (result.snippet.isNotEmpty) buffer.write('\n${result.snippet}');
      final page = i < pages.length ? pages[i] : null;
      if (page != null && page.text.isNotEmpty) {
        buffer.write('\nPage excerpt:\n${page.text}');
      }
    }
    return buffer.toString();
  }

  static String providerLabel(WebSearchProviderKind kind) => switch (kind) {
    WebSearchProviderKind.searxng => 'SearXNG',
    WebSearchProviderKind.brave => 'Brave Search',
    WebSearchProviderKind.tavily => 'Tavily',
  };
}
