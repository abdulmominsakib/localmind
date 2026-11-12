import 'dart:convert';

/// A URL as a URL parser resolves it.
///
/// [search] and [hash] include their leading `?` and `#`, or are empty.
typedef ParsedUrl = ({
  String href,
  String username,
  String password,
  String search,
  String hash,
});

/// Parses a source URL for [redactUrlSecrets], or returns null.
typedef ParseUrl = ParsedUrl? Function(String url);

/// Returns [text] with URL secrets redacted.
///
/// First, for each of [sourceUrls], these texts are replaced wherever they
/// occur as written, percent-decoded, percent-encoded or JSON-escaped, also
/// as [parseUrl] parses the URL:
/// - the URL and its parsed `href`, when the URL starts with `//`
///   or `scheme://`, become its display form (below);
/// - `?query` and `#fragment` are removed after any non-space character;
/// - the userinfo and password are removed as whole tokens of any length;
/// - the query and each `&`-separated part that contain `=` are removed as
///   whole tokens, and so are a bare value (after `=`, or a part without `=`)
///   and the fragment when they have at least 10 characters. Shorter bare
///   values, such as `1` in `?v=1`, stay in the text.
///
/// A whole token is not preceded or followed by an ASCII letter or digit.
/// Slashless HTTP(S), FTP, WS and WSS userinfo URLs are treated as authority URLs.
/// Userinfo runs from after `//` to the last `@` of the authority, and to the
/// last `@` of the URL.
///
/// Then, as a best-effort backstop for other URLs, each whitespace-separated
/// word, without its leading opening and trailing closing quotes, brackets
/// and punctuation, is treated as a URL when it contains `://`, starts with
/// `/`, `./`, `../` or `host.name[:port]/` (optionally after userinfo), is a
/// dotted file name followed by `?` or `#`, or has a `?` or `#` part
/// containing `=`. From a leading `//`, or its first `scheme://` before any
/// `?` or `#`, the rest of the word becomes its display form; otherwise the
/// word loses everything from its first `?` or `#`, then a leading `user@`
/// or `user:password@`.
///
/// The display form is `[scheme:]//host[:port]/path`. The authority runs from
/// after `//` to the first `/`, `?`, `#` or `\`, and the host follows its
/// last `@`. When the authority has no `@` and is not a `host[:port]`, the
/// host follows the last `@` before the first `?` or `#` instead. The host is
/// left out when neither applies, when an authority with an `@` and an empty
/// or `/` path is followed by `?` or `#` and then another `@`, or, for a
/// source URL, when the display form would contain its known credentials or
/// credential/signature query values.
String redactUrlSecrets(
  String text, {
  Iterable<String> sourceUrls = const <String>[],
  ParseUrl? parseUrl,
}) => _removeSourceUrlSecrets(
  text,
  sourceUrls,
  parseUrl,
).replaceAllMapped(_word, (match) => _redactWord(match[0]!));

/// The display form of a source [url], as [redactUrlSecrets] describes it.
String sourceUrlDisplay(String url, {ParseUrl? parseUrl}) =>
    _sourceDisplayUrl(url, parseUrl);

/// Redacts URL diagnostics in an explicit model [path].
///
/// Authority URLs and paths with query or fragment key/value syntax can carry
/// browser credentials. Other native filename literals remain unchanged.
String sourcePathDisplay(String path) {
  if (_authorityStart(path) < 0 && !_queryOrFragmentWithValue.hasMatch(path)) {
    return path;
  }
  return redactUrlSecrets(path, sourceUrls: <String>[path]);
}

final RegExp _word = RegExp(r'\S+');
final RegExp _wordParts = RegExp(r'''^(["'(<\[]*)(.*?)(["')\]>.,;:!]*)$''');
final RegExp _hostPath = RegExp(
  r'^(?:[^\s/@]+@)?[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+(?::\d+)?/',
);
final RegExp _fileWithQueryOrFragment = RegExp(r'^[\w.-]*\w\.\w+[?#]');
final RegExp _queryOrFragmentWithValue = RegExp(r'[?#][^\s?#=]*=');
final RegExp _leadingUserInfo = RegExp(r'^[^\s/@]+@');
final RegExp _schemeAndSlashes = RegExp(r'[A-Za-z][A-Za-z0-9+.-]*://');
final RegExp _slashlessAuthority = RegExp(
  r'^(?:https?|ftp|wss?):(?=[^/?#\s]*@)',
  caseSensitive: false,
);
final RegExp _authorityEnd = RegExp(r'[/?#\\]');
final RegExp _queryOrFragment = RegExp('[?#]');
final RegExp _hostAndPort = RegExp(
  r'^(?:[^\s/?#@\\:\[\]"<>]*|\[[0-9A-Fa-f:.]+\])(?::\d*)?$',
);
final RegExp _secretQueryKey = RegExp(
  r'^(?:token|access_token|auth|authorization|password|passwd|secret|sig|signature|api[-_]?key|key|x-amz-(?:signature|credential|security-token)|x-goog-(?:signature|credential))$',
  caseSensitive: false,
);
final RegExp _percentEscapes = RegExp('(?:%[0-9A-Fa-f]{2})+');

String _removeSourceUrlSecrets(
  String text,
  Iterable<String> sourceUrls,
  ParseUrl? parseUrl,
) {
  final wholes = <String, String>{};
  final delimited = <String>{};
  final tokens = <String>{};
  for (final url in sourceUrls) {
    final parsedUrl = parseUrl?.call(url);
    final secrets = _SourceUrlSecrets(url, parsedUrl);
    if (_authorityStart(url) >= 0) {
      final display = _sourceDisplayUrl(url, parseUrl, secrets);
      for (final whole in <String>[
        url,
        if (parsedUrl != null) parsedUrl.href,
      ]) {
        for (final form in _encodedForms(whole)) {
          wholes[form] = display;
        }
      }
    }
    for (final secret in secrets.delimited) {
      delimited.addAll(_encodedForms(secret));
    }
    for (final secret in <String>{
      ...secrets.credentials,
      ...secrets.tokens,
      ...secrets.sensitiveQueryValues,
    }) {
      tokens.addAll(_encodedForms(secret));
    }
  }
  String alternatives(Iterable<String> forms) {
    final sorted = forms.where((form) => form.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return sorted.map(RegExp.escape).join('|');
  }

  final patterns = <String>[
    if (alternatives(wholes.keys) case final whole when whole.isNotEmpty)
      '(?:$whole)',
    if (alternatives(delimited) case final after when after.isNotEmpty)
      '(?<=\\S)(?:$after)(?![A-Za-z0-9])',
    if (alternatives(tokens) case final token when token.isNotEmpty)
      '(?<![A-Za-z0-9])(?:$token)(?![A-Za-z0-9])',
  ];
  if (patterns.isEmpty) return text;
  return text.replaceAllMapped(
    RegExp(patterns.join('|')),
    (match) => wholes[match[0]!] ?? '',
  );
}

/// Bare query values and fragments shorter than this stay in error text.
const int _minimumBareValueLength = 10;

/// Secrets of a source URL, grouped by how error text loses them.
class _SourceUrlSecrets {
  _SourceUrlSecrets(this.url, ParsedUrl? parsedUrl) {
    _addQueryAndFragment(0);
    final start = _authorityStart(url);
    if (start >= 0) {
      final end = url.indexOf(_authorityEnd, start);
      final authority = url.substring(start, end < 0 ? url.length : end);
      final authorityAt = authority.lastIndexOf('@');
      if (authorityAt >= 0) {
        _addUserInfo(authority.substring(0, authorityAt), parsed: true);
      }
      final lastAt = url.lastIndexOf('@');
      if (lastAt >= start && lastAt != start + authorityAt) {
        _addUserInfo(url.substring(start, lastAt), parsed: false);
        _addQueryAndFragment(lastAt + 1);
      }
    }
    if (start < 0) {
      final userInfo = _leadingUserInfo.matchAsPrefix(url);
      if (userInfo != null) {
        _addUserInfo(url.substring(0, userInfo.end - 1), parsed: true);
      }
    }
    if (parsedUrl != null) {
      final username = parsedUrl.username;
      final password = parsedUrl.password;
      _addUserInfo(
        password.isEmpty ? username : '$username:$password',
        parsed: true,
      );
      if (parsedUrl.search.isNotEmpty) {
        _addQuery(parsedUrl.search.substring(1));
      }
      if (parsedUrl.hash.isNotEmpty) {
        _addFragment(parsedUrl.hash.substring(1));
      }
    }
  }

  final String url;

  /// Userinfo spans and passwords, removed as whole tokens at any length.
  final Set<String> credentials = <String>{};

  /// The [credentials] of the authority as [ParseUrl] parses it, which a
  /// display form must not contain.
  final Set<String> parsedCredentials = <String>{};

  /// `?query` and `#fragment`, removed wherever they follow a non-space.
  final Set<String> delimited = <String>{};

  /// Queries and `&`-separated parts that contain `=`, and bare values and
  /// fragments of at least [_minimumBareValueLength] characters, removed as
  /// whole tokens.
  final Set<String> tokens = <String>{};

  /// Explicit credential/signature query values that must not reappear in a display path.
  final Set<String> sensitiveQueryValues = <String>{};

  void _addUserInfo(String userInfo, {required bool parsed}) {
    final colon = userInfo.indexOf(':');
    for (final secret in <String>[
      userInfo,
      if (colon >= 0) userInfo.substring(colon + 1),
      if (colon >= 0) userInfo.substring(userInfo.lastIndexOf(':') + 1),
    ]) {
      if (secret.isEmpty) continue;
      credentials.add(secret);
      if (parsed) parsedCredentials.add(secret);
    }
  }

  void _addQueryAndFragment(int from) {
    final fragment = url.indexOf('#', from);
    final query = url.indexOf('?', from);
    if (fragment >= 0) _addFragment(url.substring(fragment + 1));
    if (query >= 0 && (fragment < 0 || query < fragment)) {
      _addQuery(url.substring(query + 1, fragment < 0 ? null : fragment));
    }
  }

  void _addQuery(String query) {
    if (query.isEmpty) return;
    delimited.add('?$query');
    _addToken(query);
    for (final part in query.split('&')) {
      _addToken(part);
      final equals = part.indexOf('=');
      if (equals >= 0) {
        final value = part.substring(equals + 1);
        _addToken(value);
        if (_secretQueryKey.hasMatch(
          _percentDecoded(part.substring(0, equals)),
        )) {
          if (value.isNotEmpty) sensitiveQueryValues.add(value);
        }
      }
    }
  }

  void _addFragment(String fragment) {
    if (fragment.isEmpty) return;
    delimited.add('#$fragment');
    _addToken(fragment);
  }

  void _addToken(String value) {
    if (value.contains('=') || value.length >= _minimumBareValueLength) {
      tokens.add(value);
    }
  }
}

Set<String> _encodedForms(String text) {
  final forms = <String>{text};
  void add(String Function() form) {
    try {
      forms.add(form());
    } catch (_) {}
  }

  add(() => Uri.encodeComponent(text));
  add(() => Uri.encodeFull(text));
  add(() {
    final json = jsonEncode(text);
    return json.substring(1, json.length - 1);
  });
  add(() {
    final json = jsonEncode(text);
    return json.substring(1, json.length - 1).replaceAll('/', r'\/');
  });
  for (final decoded in <String>[
    _percentDecoded(text),
    _percentDecoded(text.replaceAll('+', ' ')),
  ]) {
    forms.add(decoded);
    add(() => Uri.encodeComponent(decoded));
  }
  return forms;
}

String _percentDecoded(String text) => text.replaceAllMapped(
  _percentEscapes,
  (match) => utf8.decode(<int>[
    for (var i = 0; i < match[0]!.length; i += 3)
      int.parse(match[0]!.substring(i + 1, i + 3), radix: 16),
  ], allowMalformed: true),
);

int _authorityStart(String url) {
  if (url.startsWith('//')) return 2;
  return _schemeAndSlashes.matchAsPrefix(url)?.end ??
      _slashlessAuthority.matchAsPrefix(url)?.end ??
      -1;
}

String _redactWord(String word) {
  final parts = _wordParts.firstMatch(word)!;
  final url = parts[2]!.replaceAll(r'\/', '/');
  final isUrl =
      url.contains('://') ||
      _slashlessAuthority.hasMatch(url) ||
      url.startsWith('/') ||
      url.startsWith('./') ||
      url.startsWith('../') ||
      _hostPath.hasMatch(url) ||
      _fileWithQueryOrFragment.hasMatch(url) ||
      _queryOrFragmentWithValue.hasMatch(url);
  if (!isUrl) return word;
  return '${parts[1]}${_redactUrl(url)}${parts[3]}';
}

String _redactUrl(String url) {
  if (url.startsWith('//') || _slashlessAuthority.hasMatch(url)) {
    return _displayUrl(url);
  }
  final scheme = _schemeAndSlashes.firstMatch(url);
  final end = url.indexOf(_queryOrFragment);
  if (scheme != null && (end < 0 || scheme.start < end)) {
    return url.substring(0, scheme.start) +
        _displayUrl(url.substring(scheme.start));
  }
  final base = end < 0 ? url : url.substring(0, end);
  return base.replaceFirst(_leadingUserInfo, '');
}

/// The display form of a source [url], without its host when the display
/// form would contain one of its known credentials or credential/signature query values.
String _sourceDisplayUrl(
  String url,
  ParseUrl? parseUrl, [
  _SourceUrlSecrets? secrets,
]) {
  final display = _displayUrl(url);
  final start = _authorityStart(url);
  secrets ??= _SourceUrlSecrets(url, parseUrl?.call(url));
  for (final secret in <String>{
    ...secrets.parsedCredentials,
    ...secrets.sensitiveQueryValues,
  }) {
    for (final form in _encodedForms(secret)) {
      if (form.isNotEmpty &&
          (secrets.parsedCredentials.contains(secret)
              ? display.contains(form)
              : RegExp(
                  '(?<![A-Za-z0-9])${RegExp.escape(form)}(?![A-Za-z0-9])',
                ).hasMatch(display))) {
        return start < 0
            ? '<redacted-url>'
            : url.substring(0, start).toLowerCase();
      }
    }
  }
  return display;
}

String _displayUrl(String url) {
  final slashless = _slashlessAuthority.matchAsPrefix(url);
  if (slashless != null && !_schemeAndSlashes.hasMatch(url)) {
    return _displayUrl(
      '${url.substring(0, slashless.end)}//${url.substring(slashless.end)}',
    );
  }
  final start = _authorityStart(url);
  if (start < 0) {
    final end = url.indexOf(_queryOrFragment);
    final base = end < 0 ? url : url.substring(0, end);
    if (_leadingUserInfo.hasMatch(base)) {
      return base.replaceFirst(_leadingUserInfo, '');
    }
    final uri = Uri.tryParse(base);
    if (uri == null) return base;
    return Uri(
      scheme: uri.hasScheme ? uri.scheme : null,
      host: uri.hasAuthority ? uri.host : null,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
  final prefix = url.substring(0, start).toLowerCase();
  var end = url.indexOf(_authorityEnd, start);
  if (end < 0) end = url.length;
  final authority = url.substring(start, end);
  final at = authority.lastIndexOf('@');
  String? host = at < 0 ? authority : authority.substring(at + 1);
  if (at >= 0) {
    final pathEnd = url.indexOf(_queryOrFragment, end);
    final path = pathEnd < 0 ? '' : url.substring(end, pathEnd);
    if (pathEnd >= 0 &&
        (path.isEmpty || path == '/') &&
        url.indexOf('@', pathEnd) >= 0) {
      host = null;
    }
  } else if (!_hostAndPort.hasMatch(authority)) {
    final queryStart = url.indexOf(_queryOrFragment, start);
    final lastAt = url
        .substring(0, queryStart < 0 ? url.length : queryStart)
        .lastIndexOf('@');
    host = null;
    if (lastAt >= start) {
      end = url.indexOf(_authorityEnd, lastAt + 1);
      if (end < 0) end = url.length;
      host = url.substring(lastAt + 1, end);
    }
  }
  if (host == null) return prefix;
  final rest = url.substring(end);
  final queryStart = rest.indexOf(_queryOrFragment);
  var path = queryStart < 0 ? rest : rest.substring(0, queryStart);
  if (path.contains('://')) path = _redactUrl(path);
  final uri = Uri.tryParse('$prefix$host$path');
  if (uri == null) return '$prefix$host$path';
  return Uri(
    scheme: uri.hasScheme ? uri.scheme : null,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}
