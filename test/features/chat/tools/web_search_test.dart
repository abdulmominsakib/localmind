import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/tools/web/web_page_fetcher.dart';
import 'package:localmind/features/chat/data/tools/web/web_search_client.dart';
import 'package:localmind/features/chat/data/tools/web/web_search_service.dart';
import 'package:localmind/features/chat/data/tools/web/web_tool_provider.dart';
import 'package:localmind/features/chat/providers/web_search_next_provider.dart';

/// Answers every request with one canned response and records the request.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body, {this.status = 200, this.contentType});

  final String body;
  final int status;
  final String? contentType;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType ?? 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_CannedAdapter adapter) => Dio()..httpClientAdapter = adapter;

class _NoKeys extends WebSearchKeyStore {
  @override
  Future<String?> read(WebSearchProviderKind kind) async => null;
}

class _FakeClient implements WebSearchClient {
  _FakeClient(this.results);

  final List<WebSearchResult> results;
  String? lastQuery;

  @override
  Future<List<WebSearchResult>> search(String query, {int count = 5}) async {
    lastQuery = query;
    return results.take(count).toList();
  }
}

class _FakeFetcher extends WebPageFetcher {
  @override
  Future<WebPage> fetch(String rawUrl, {int maxChars = 6000}) async {
    if (rawUrl.contains('broken')) throw const WebSearchException('nope');
    return WebPage(
      url: rawUrl,
      title: 'Page',
      text: 'Body of $rawUrl',
      truncated: false,
    );
  }
}

void main() {
  group('WebPageFetcher', () {
    test('accepts only http and https links', () {
      expect(WebPageFetcher.parseUrl('https://example.com/a'), isNotNull);
      expect(WebPageFetcher.parseUrl('http://example.com'), isNotNull);
      expect(WebPageFetcher.parseUrl('file:///etc/passwd'), isNull);
      expect(WebPageFetcher.parseUrl('javascript:alert(1)'), isNull);
      expect(WebPageFetcher.parseUrl('not a url'), isNull);
    });

    test('keeps the main text and drops scripts and navigation', () {
      final (:title, :text) = WebPageFetcher.extractReadableText('''
<html><head><title>Hello &amp; welcome</title><style>p{}</style></head>
<body>
  <nav>Home | About</nav>
  <script>var secret = 1;</script>
  <article><h1>Headline</h1><p>First paragraph.</p>
  <ul><li>One</li><li>Two</li></ul></article>
  <footer>Copyright</footer>
</body></html>''');
      expect(title, 'Hello & welcome');
      expect(text, contains('Headline'));
      expect(text, contains('First paragraph.'));
      expect(text, contains('- One'));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('Home | About')));
      expect(text, isNot(contains('Copyright')));
    });

    test('rejects pages that are not text', () async {
      final fetcher = WebPageFetcher(
        dio: _dio(_CannedAdapter('PNG', contentType: 'image/png')),
      );
      expect(
        fetcher.fetch('https://example.com/x.png'),
        throwsA(isA<WebSearchException>()),
      );
    });

    test('shortens long pages', () async {
      final fetcher = WebPageFetcher(
        dio: _dio(
          _CannedAdapter(
            '<html><body><p>${'word ' * 500}</p></body></html>',
            contentType: 'text/html; charset=utf-8',
          ),
        ),
      );
      final page = await fetcher.fetch('https://example.com', maxChars: 100);
      expect(page.truncated, isTrue);
      expect(page.text.length, lessThanOrEqualTo(101));
    });
  });

  group('search clients', () {
    test('SearXNG reads results from the JSON format', () async {
      final adapter = _CannedAdapter(
        jsonEncode({
          'results': [
            {
              'title': 'Dart',
              'url': 'https://dart.dev',
              'content': 'The <b>Dart</b> language',
            },
            {'title': 'No link'},
          ],
        }),
      );
      final client = SearxngSearchClient(
        'https://searx.test/',
        dio: _dio(adapter),
      );
      final results = await client.search('dart lang', count: 5);
      expect(results, hasLength(1));
      expect(results.first.title, 'Dart');
      expect(results.first.snippet, 'The Dart language');
      expect(adapter.last!.uri.path, '/search');
      expect(adapter.last!.uri.queryParameters['format'], 'json');
      expect(adapter.last!.uri.queryParameters['q'], 'dart lang');
    });

    test('SearXNG explains a disabled JSON format', () async {
      final client = SearxngSearchClient(
        'https://searx.test',
        dio: _dio(
          _CannedAdapter('Forbidden', status: 403, contentType: 'text/html'),
        ),
      );
      expect(
        client.search('x'),
        throwsA(
          isA<WebSearchException>().having(
            (e) => e.message,
            'message',
            contains('json'),
          ),
        ),
      );
    });

    test('Brave sends the key and reads web results', () async {
      final adapter = _CannedAdapter(
        jsonEncode({
          'web': {
            'results': [
              {'title': 'A', 'url': 'https://a.test', 'description': 'Snippet'},
            ],
          },
        }),
      );
      final results = await BraveSearchClient(
        'key-1',
        dio: _dio(adapter),
      ).search('q');
      expect(results.single.url, 'https://a.test');
      expect(adapter.last!.headers['X-Subscription-Token'], 'key-1');
    });

    test('Tavily reports a bad key', () async {
      final client = TavilySearchClient(
        'bad',
        dio: _dio(_CannedAdapter('{}', status: 401)),
      );
      expect(client.search('q'), throwsA(isA<WebSearchException>()));
    });
  });

  group('WebSearchService', () {
    WebSearchService service(WebSearchClient? client) => WebSearchService(
      kind: WebSearchProviderKind.brave,
      searxngUrl: '',
      keyStore: _NoKeys(),
      client: client,
      fetcher: _FakeFetcher(),
    );

    test('is not configured without a key', () async {
      expect(await service(null).isConfigured(), isFalse);
    });

    test('builds numbered context with page excerpts', () async {
      final client = _FakeClient(const [
        WebSearchResult(title: 'One', url: 'https://one.test', snippet: 's1'),
        WebSearchResult(
          title: 'Two',
          url: 'https://broken.test',
          snippet: 's2',
        ),
        WebSearchResult(title: 'Three', url: 'https://three.test', snippet: ''),
      ]);
      final context = await service(
        client,
      ).buildContext('  what is new  ', now: DateTime(2026, 11, 25));
      expect(client.lastQuery, 'what is new');
      expect(context, contains('2026-11-25'));
      expect(context, contains('[1] One'));
      expect(context, contains('Body of https://one.test'));
      expect(context, contains('[2] Two'));
      expect(context, isNot(contains('Body of https://broken.test')));
      expect(context, contains('[3] Three'));
      expect(context, isNot(contains('Body of https://three.test')));
    });

    test('tells the model when nothing was found', () async {
      final context = await service(_FakeClient(const [])).buildContext('q');
      expect(context, contains('no results'));
    });

    test('tells the model when the search failed', () async {
      final context = await service(null).buildContext('q');
      expect(context, contains('failed'));
    });
  });

  group('WebToolProvider', () {
    final configured = WebSearchService(
      kind: WebSearchProviderKind.searxng,
      searxngUrl: 'https://searx.test',
      keyStore: _NoKeys(),
      client: _FakeClient(const [
        WebSearchResult(title: 'T', url: 'https://t.test', snippet: 'x'),
      ]),
    );

    test('offers no tools when web search is off', () async {
      final tools = await WebToolProvider(
        service: configured,
        enabled: false,
      ).listTools();
      expect(tools, isEmpty);
    });

    test('offers search and fetch when on', () async {
      final tools = await WebToolProvider(service: configured).listTools();
      expect(tools.map((t) => t.name), [
        WebToolProvider.searchTool,
        WebToolProvider.fetchTool,
      ]);
    });

    test('returns results as JSON', () async {
      final result = await WebToolProvider(
        service: configured,
      ).execute(WebToolProvider.searchTool, {'query': 'q'});
      expect(result.success, isTrue);
      expect(jsonDecode(result.output), [
        {'title': 'T', 'url': 'https://t.test', 'snippet': 'x'},
      ]);
    });
  });

  test('search-the-web switch is used once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(webSearchNextProvider.notifier);
    notifier.set(true);
    expect(container.read(webSearchNextProvider), isTrue);
    expect(notifier.take(), isTrue);
    expect(container.read(webSearchNextProvider), isFalse);
    expect(notifier.take(), isFalse);
  });
}
