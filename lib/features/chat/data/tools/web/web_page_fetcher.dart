import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'web_search_client.dart';

class WebPage {
  const WebPage({
    required this.url,
    required this.title,
    required this.text,
    this.truncated = false,
  });

  final String url;
  final String title;
  final String text;
  final bool truncated;
}

/// Downloads a page and reduces it to readable text for a model.
class WebPageFetcher {
  WebPageFetcher({
    Dio? dio,
    this.maxBytes = 2 * 1024 * 1024,
    this.timeout = const Duration(seconds: 15),
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final int maxBytes;
  final Duration timeout;

  /// Only public http(s) pages; never local files or other schemes.
  static Uri? parseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  Future<WebPage> fetch(String rawUrl, {int maxChars = 6000}) async {
    final uri = parseUrl(rawUrl);
    if (uri == null) {
      throw const WebSearchException('Only http and https links can be read.');
    }
    final Response<List<int>> response;
    try {
      response = await _dio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {
            'Accept': 'text/html,text/plain;q=0.9,*/*;q=0.1',
            'User-Agent': 'Mozilla/5.0 (Mobile; LocalMind) AppleWebKit/537.36',
          },
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      throw WebSearchException(
        status != null
            ? 'The page answered HTTP $status.'
            : 'Could not load the page: ${e.message}',
      );
    }

    final bytes = response.data ?? const <int>[];
    final limited = bytes.length > maxBytes
        ? bytes.sublist(0, maxBytes)
        : bytes;
    final body = _decodeUtf8(limited) ?? String.fromCharCodes(limited);
    final contentType = response.headers.value('content-type') ?? '';
    final finalUrl = response.realUri.toString();

    if (contentType.contains('text/plain')) {
      return _cut(finalUrl, '', _normalize(body), maxChars);
    }
    if (contentType.isNotEmpty &&
        !contentType.contains('html') &&
        !contentType.contains('xml')) {
      throw WebSearchException('That link is not a web page ($contentType).');
    }
    final extracted = extractReadableText(body);
    return _cut(finalUrl, extracted.title, extracted.text, maxChars);
  }

  static String? _decodeUtf8(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (_) {
      return null;
    }
  }

  static WebPage _cut(String url, String title, String text, int maxChars) {
    if (text.length <= maxChars) {
      return WebPage(url: url, title: title, text: text);
    }
    return WebPage(
      url: url,
      title: title,
      text: '${text.substring(0, maxChars).trimRight()}…',
      truncated: true,
    );
  }

  static const _dropTags = [
    'script',
    'style',
    'noscript',
    'svg',
    'iframe',
    'form',
    'nav',
    'header',
    'footer',
    'aside',
    'button',
    'template',
  ];

  static const _blockTags = {
    'p',
    'div',
    'section',
    'article',
    'li',
    'tr',
    'br',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'blockquote',
    'table',
    'ul',
    'ol',
    'dd',
    'dt',
  };

  /// Visible text of the page's main content, one block per line.
  static ({String title, String text}) extractReadableText(String html) {
    final document = html_parser.parse(html);
    final title = _normalize(document.querySelector('title')?.text ?? '');
    for (final tag in _dropTags) {
      for (final element in document.querySelectorAll(tag)) {
        element.remove();
      }
    }
    final root =
        document.querySelector('article') ??
        document.querySelector('main') ??
        document.querySelector('[role=main]') ??
        document.body;
    if (root == null) return (title: title, text: '');

    final buffer = StringBuffer();
    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text);
        return;
      }
      if (node is! dom.Element) return;
      final isBlock = _blockTags.contains(node.localName);
      if (isBlock) buffer.write('\n');
      if (node.localName == 'li') buffer.write('- ');
      for (final child in node.nodes) {
        walk(child);
      }
      if (isBlock) buffer.write('\n');
    }

    walk(root);
    final lines = buffer
        .toString()
        .split('\n')
        .map(_normalize)
        .where((line) => line.isNotEmpty && line != '-')
        .toList();
    return (title: title, text: lines.join('\n'));
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
}
