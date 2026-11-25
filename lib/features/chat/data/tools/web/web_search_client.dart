import 'package:dio/dio.dart';

/// Where built-in web search sends queries.
enum WebSearchProviderKind {
  /// A SearXNG instance, usually self-hosted. Needs `json` in its
  /// `search.formats` setting.
  searxng,
  brave,
  tavily;

  bool get needsApiKey => this != WebSearchProviderKind.searxng;

  static WebSearchProviderKind parse(Object? raw) =>
      WebSearchProviderKind.values.firstWhere(
        (kind) => kind.name == raw,
        orElse: () => WebSearchProviderKind.searxng,
      );
}

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  final String title;
  final String url;
  final String snippet;

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    if (snippet.isNotEmpty) 'snippet': snippet,
  };
}

class WebSearchException implements Exception {
  const WebSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One search backend.
abstract class WebSearchClient {
  Future<List<WebSearchResult>> search(String query, {int count = 5});
}

final _tagPattern = RegExp(r'<[^>]+>');
final _spacePattern = RegExp(r'\s+');

/// Search APIs wrap matches in `<strong>` and similar; keep plain text.
String _plain(Object? value) => (value?.toString() ?? '')
    .replaceAll(_tagPattern, '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(_spacePattern, ' ')
    .trim();

List<WebSearchResult> _results(
  Object? list, {
  required String snippetKey,
  required int count,
}) {
  if (list is! List) return const [];
  final results = <WebSearchResult>[];
  for (final item in list) {
    if (item is! Map) continue;
    final url = item['url']?.toString() ?? '';
    if (!url.startsWith('http')) continue;
    results.add(
      WebSearchResult(
        title: _plain(item['title']).isEmpty ? url : _plain(item['title']),
        url: url,
        snippet: _plain(item[snippetKey]),
      ),
    );
    if (results.length >= count) break;
  }
  return results;
}

Never _fail(DioException e, String provider) {
  final status = e.response?.statusCode;
  if (status == 401 || status == 403) {
    throw WebSearchException('$provider rejected the API key or URL.');
  }
  if (status == 429) {
    throw WebSearchException('$provider rate limit or quota reached.');
  }
  if (status != null) {
    throw WebSearchException('$provider answered HTTP $status.');
  }
  final reason = e.message ?? e.error?.toString();
  throw WebSearchException(
    reason == null || reason.isEmpty
        ? 'Could not reach $provider.'
        : 'Could not reach $provider: $reason',
  );
}

class SearxngSearchClient implements WebSearchClient {
  SearxngSearchClient(this.baseUrl, {Dio? dio}) : _dio = dio ?? Dio();

  final String baseUrl;
  final Dio _dio;

  @override
  Future<List<WebSearchResult>> search(String query, {int count = 5}) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const WebSearchException('No SearXNG URL is set.');
    }
    try {
      final response = await _dio.get<Object?>(
        '$base/search',
        queryParameters: {'q': query, 'format': 'json'},
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is! Map) {
        throw const WebSearchException(
          'SearXNG did not return JSON. Enable the json format in its '
          'settings.yml (search.formats).',
        );
      }
      return _results(data['results'], snippetKey: 'content', count: count);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw const WebSearchException(
          'SearXNG refused JSON results. Enable the json format in its '
          'settings.yml (search.formats).',
        );
      }
      _fail(e, 'SearXNG');
    }
  }
}

class BraveSearchClient implements WebSearchClient {
  BraveSearchClient(this.apiKey, {Dio? dio}) : _dio = dio ?? Dio();

  final String apiKey;
  final Dio _dio;

  @override
  Future<List<WebSearchResult>> search(String query, {int count = 5}) async {
    try {
      final response = await _dio.get<Object?>(
        'https://api.search.brave.com/res/v1/web/search',
        queryParameters: {'q': query, 'count': count},
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Subscription-Token': apiKey,
          },
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      final web = data is Map ? data['web'] : null;
      return _results(
        web is Map ? web['results'] : null,
        snippetKey: 'description',
        count: count,
      );
    } on DioException catch (e) {
      _fail(e, 'Brave Search');
    }
  }
}

class TavilySearchClient implements WebSearchClient {
  TavilySearchClient(this.apiKey, {Dio? dio}) : _dio = dio ?? Dio();

  final String apiKey;
  final Dio _dio;

  @override
  Future<List<WebSearchResult>> search(String query, {int count = 5}) async {
    try {
      final response = await _dio.post<Object?>(
        'https://api.tavily.com/search',
        data: {'query': query, 'max_results': count},
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      return _results(
        data is Map ? data['results'] : null,
        snippetKey: 'content',
        count: count,
      );
    } on DioException catch (e) {
      _fail(e, 'Tavily');
    }
  }
}
