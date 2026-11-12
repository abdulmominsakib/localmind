/// Vendors the pinned WebGPU bridge assets into a Flutter Web app for
/// `dart run llamadart:web_setup`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/exceptions.dart';

/// The asset repository that publishes the pinned bridge release.
const String webBridgeAssetsRepository = 'leehack/llama-web-bridge-assets';

/// The bridge asset release this llamadart version is qualified against.
const String webBridgeAssetsTag = 'v0.1.83';

/// SHA-256 of the exact approved `manifest.json` of [webBridgeAssetsTag].
///
/// The manifest lists the SHA-256 and size of every asset, so pinning its
/// bytes pins every file the tool writes.
const String webBridgeManifestSha256 =
    'ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5';

/// Directory under the app's `web/` directory that receives the assets.
const String webBridgeAssetsDirName = 'webgpu_bridge';

/// The files the bootstrap snippet loads at runtime.
const List<String> webBridgeRuntimeFiles = <String>[
  'llama_webgpu_bridge.js',
  'llama_webgpu_bridge_worker.js',
  'llama_webgpu_core.js',
  'llama_webgpu_core.wasm',
  'llama_webgpu_core_mem64.js',
  'llama_webgpu_core_mem64.wasm',
];

const String _manifestFileName = 'manifest.json';
const int _maxManifestBytes = 64 * 1024;
const String _beginMarker = '<!-- llamadart:web_setup:begin -->';
const String _endMarker = '<!-- llamadart:web_setup:end -->';
final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
final RegExp _flutterBootstrapScript = RegExp(
  r'''^([ \t]*)<script\b[^>]*\bsrc=["'](?:\./)?flutter_bootstrap\.js["']''',
  multiLine: true,
);
final RegExp _headClose = RegExp(r'^([ \t]*)</head>', multiLine: true);
final RegExp _rawTextOpen = RegExp(
  r'<(script|style)(?=[\s/>])',
  caseSensitive: false,
);
final RegExp _srcAttribute = RegExp(
  r'''\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  caseSensitive: false,
);
final RegExp _bridgeModule = RegExp(r'llama_webgpu_bridge\.js');
final RegExp _bridgeModuleImport = RegExp(
  r'\bimport\b[^;]*?llama_webgpu_bridge\.js',
);
final RegExp _bridgeGlobalAssignment = RegExp(
  r'''(?<![\w$.])(?:(?:window|globalThis|self)\s*\.\s*)?LlamaWebGpuBridge\s*=(?![=>])'''
  r'''|(?<![\w$.])(?:window|globalThis|self)\s*\[\s*["']LlamaWebGpuBridge["']\s*\]\s*=(?![=>])''',
);
const int _maxExcerptChars = 80;
const String _byteOrderMark = '\uFEFF';

/// A bridge asset release identified by the SHA-256 of its manifest.
final class WebBridgePin {
  /// Creates a pin for [tag] of [repository] whose `manifest.json` hashes to
  /// [manifestSha256].
  const WebBridgePin({
    required this.repository,
    required this.tag,
    required this.manifestSha256,
  });

  /// `owner/name` of the asset repository.
  final String repository;

  /// Release tag of the assets.
  final String tag;

  /// Lowercase hex SHA-256 of the release's `manifest.json` bytes.
  final String manifestSha256;

  /// The CDN directory that serves this release.
  Uri get baseUri => Uri.parse('https://cdn.jsdelivr.net/gh/$repository@$tag/');
}

/// The pin this llamadart version ships with.
const WebBridgePin pinnedWebBridge = WebBridgePin(
  repository: webBridgeAssetsRepository,
  tag: webBridgeAssetsTag,
  manifestSha256: webBridgeManifestSha256,
);

/// Thrown when the web setup cannot complete; [message] says what to fix.
final class WebSetupException extends LlamaException {
  /// Creates an exception with an actionable [message].
  WebSetupException(super.message);

  @override
  String toString() => 'WebSetupException: $message';
}

/// Opens [url] and returns its body; throws on a non-success response.
typedef WebBridgeFetch = Future<Stream<List<int>>> Function(Uri url);

/// What [setUpWebBridge] changed.
final class WebSetupResult {
  /// Creates a result.
  const WebSetupResult({
    required this.assetsDir,
    required this.downloaded,
    required this.unchanged,
    required this.indexHtmlUpdated,
  });

  /// Directory that holds the assets.
  final Directory assetsDir;

  /// Files that were fetched and verified in this run.
  final List<String> downloaded;

  /// Files that already matched the manifest.
  final List<String> unchanged;

  /// Whether `index.html` was written.
  final bool indexHtmlUpdated;
}

/// Downloads the [pin]ned bridge assets into `<webDir>/webgpu_bridge/`,
/// verifies each against the pinned manifest, and adds the bootstrap snippet
/// to `<webDir>/index.html` when [patchIndexHtml] is true.
///
/// Files that already match the manifest are not fetched again, and an
/// up-to-date `index.html` is not rewritten, so rerunning is a no-op.
/// `index.html` is validated before any download, and a file is replaced
/// only after its download verified. Throws
/// [WebSetupException] on any failure.
Future<WebSetupResult> setUpWebBridge({
  required Directory webDir,
  WebBridgePin pin = pinnedWebBridge,
  WebBridgeFetch? fetch,
  bool patchIndexHtml = true,
  void Function(String message)? log,
}) async {
  final File indexHtml = _requireWebDir(webDir, needIndexHtml: patchIndexHtml);
  final String? html = patchIndexHtml ? _readText(indexHtml) : null;
  final String? patched = html == null
      ? null
      : patchWebBridgeIndexHtml(html, pin);
  final WebBridgeFetch fetchUrl = fetch ?? _httpFetch;
  final Directory assetsDir = Directory(
    p.join(webDir.path, webBridgeAssetsDirName),
  )..createSync(recursive: true);

  final File manifestFile = File(p.join(assetsDir.path, _manifestFileName));
  List<int>? manifestBytes = _readIfPinned(manifestFile, pin);
  final bool manifestWasCurrent = manifestBytes != null;
  if (manifestBytes == null) {
    final Uri url = pin.baseUri.resolve(_manifestFileName);
    log?.call('Fetching $url');
    manifestBytes = await _download(fetchUrl, url, maxBytes: _maxManifestBytes);
  }
  final Map<String, _AssetDigest> digests = _parseManifest(manifestBytes, pin);

  final downloaded = <String>[];
  final unchanged = <String>[];
  for (final String name in webBridgeRuntimeFiles) {
    final _AssetDigest digest = digests[name]!;
    final File target = File(p.join(assetsDir.path, name));
    if (await _matches(target, digest)) {
      unchanged.add(name);
      continue;
    }
    final Uri url = pin.baseUri.resolve(name);
    log?.call('Fetching $url');
    await _downloadVerified(fetchUrl, url, target, digest);
    downloaded.add(name);
  }
  if (!manifestWasCurrent) {
    _writeAtomically(manifestFile, manifestBytes);
  }

  final bool indexHtmlUpdated = patched != html;
  if (indexHtmlUpdated) {
    _writeAtomically(indexHtml, utf8.encode(patched!));
  }

  return WebSetupResult(
    assetsDir: assetsDir,
    downloaded: downloaded,
    unchanged: unchanged,
    indexHtmlUpdated: indexHtmlUpdated,
  );
}

/// Verifies an existing setup without network access.
///
/// Returns one actionable message per problem; empty means the assets match
/// the [pin]ned manifest and `index.html` carries the current snippet (when
/// [checkIndexHtml] is true). Throws [WebSetupException] when [webDir] or its
/// `index.html` is missing.
Future<List<String>> checkWebBridgeSetup({
  required Directory webDir,
  WebBridgePin pin = pinnedWebBridge,
  bool checkIndexHtml = true,
}) async {
  final File indexHtml = _requireWebDir(webDir, needIndexHtml: checkIndexHtml);
  final String assetsPath = p.join(webDir.path, webBridgeAssetsDirName);
  final File manifestFile = File(p.join(assetsPath, _manifestFileName));
  final List<int>? manifestBytes = _readIfPinned(manifestFile, pin);
  if (manifestBytes == null) {
    return <String>[
      '${manifestFile.path} is missing or is not the ${pin.tag} manifest',
    ];
  }

  final Map<String, _AssetDigest> digests = _parseManifest(manifestBytes, pin);
  final problems = <String>[];
  for (final String name in webBridgeRuntimeFiles) {
    final File file = File(p.join(assetsPath, name));
    if (!file.existsSync()) {
      problems.add('${file.path} is missing');
    } else if (!await _matches(file, digests[name]!)) {
      problems.add('${file.path} does not match the ${pin.tag} manifest');
    }
  }
  if (checkIndexHtml) {
    final String html = _readText(indexHtml);
    try {
      if (patchWebBridgeIndexHtml(html, pin) != html) {
        problems.add(
          '${indexHtml.path} lacks the current llamadart bridge bootstrap',
        );
      }
    } on _ManualLoaderException catch (error) {
      problems.add(
        '${indexHtml.path} also loads the WebGPU bridge by hand '
        '("${error.excerpt}"). Remove that loader, or skip this page with '
        '--no-index-html.',
      );
    } on WebSetupException catch (error) {
      problems.add(
        '${indexHtml.path} '
        '${error.message.replaceFirst(RegExp(r'^index\.html '), '')}',
      );
    }
  }
  return problems;
}

/// Returns [html] with the bridge bootstrap for [pin] inserted, or replacing
/// the one a previous run inserted.
///
/// A new snippet goes just before the first `flutter_bootstrap.js` script tag
/// outside an HTML comment, or before `</head>` when there is none. Throws
/// [WebSetupException] when neither exists, the markers are unbalanced, or the
/// page already loads the bridge outside the generated block.
String patchWebBridgeIndexHtml(String html, WebBridgePin pin) {
  final int begin = html.indexOf(_beginMarker);
  final int end = html.indexOf(_endMarker);
  final bool hasBegin = begin >= 0;
  final bool hasEnd = end >= 0;
  if (hasBegin != hasEnd ||
      (hasBegin &&
          (end < begin ||
              html.indexOf(_beginMarker, begin + 1) >= 0 ||
              html.indexOf(_endMarker, end + 1) >= 0))) {
    throw WebSetupException(
      'index.html has unbalanced "$_beginMarker" / "$_endMarker" markers. '
      'Remove the llamadart block by hand and rerun.',
    );
  }
  _rejectManualBridgeLoader(
    hasBegin
        ? html.substring(0, begin) + html.substring(end + _endMarker.length)
        : html,
  );
  final String newline = html.contains('\r\n') ? '\r\n' : '\n';

  if (hasBegin) {
    final int lineStart = html.lastIndexOf('\n', begin) + 1;
    final String bom = lineStart == 0 && html.startsWith(_byteOrderMark)
        ? _byteOrderMark
        : '';
    final String prefix = html.substring(lineStart + bom.length, begin);
    final String indent = RegExp(r'^[ \t]*').stringMatch(prefix)!;
    // Markup before the marker on its line stays once, on its own line.
    final String kept = prefix == indent ? '' : '${prefix.trimRight()}$newline';
    return bom +
        html.substring(0, lineStart) +
        kept +
        _indentedSnippet(pin, indent, newline) +
        html.substring(end + _endMarker.length);
  }

  final _Markup markup = _scanMarkup(html);
  final RegExpMatch? anchor =
      _firstOutside(_flutterBootstrapScript, html, markup) ??
      _firstOutside(_headClose, html, markup);
  if (anchor == null) {
    throw WebSetupException(
      'index.html has no <script src="flutter_bootstrap.js"> tag and no '
      '</head>, so the bridge bootstrap has no place to go. Add one, or '
      'rerun with --no-index-html and load the bridge yourself.',
    );
  }
  final String indent = anchor.group(1)!;
  return html.substring(0, anchor.start) +
      _indentedSnippet(pin, indent, newline) +
      newline +
      html.substring(anchor.start);
}

RegExpMatch? _firstOutside(RegExp pattern, String html, _Markup markup) {
  for (final RegExpMatch match in pattern.allMatches(html)) {
    if (!markup.isHidden(match.end - 1)) return match;
  }
  return null;
}

typedef _Range = ({int start, int end});

/// A `<script>` element outside any comment.
typedef _Script = ({int tagStart, String openTag, int bodyStart, String body});

/// The parts of a page that decide where the bootstrap may go and whether a
/// loader is already there.
final class _Markup {
  _Markup(this.hidden, this.scripts);

  /// Closed comments and the bodies of `<script>` and `<style>`.
  final List<_Range> hidden;

  /// Scripts outside comments.
  final List<_Script> scripts;

  bool isHidden(int at) =>
      hidden.any((_Range r) => at >= r.start && at < r.end);
}

/// Splits [html] into comments and raw-text elements. `<!--` inside a
/// `<script>` or `<style>` is text, and a comment that never closes is not
/// treated as one, so it cannot hide the rest of the page.
_Markup _scanMarkup(String html) {
  final hidden = <_Range>[];
  final scripts = <_Script>[];
  var at = 0;
  while (true) {
    final int lt = html.indexOf('<', at);
    if (lt < 0) break;
    if (html.startsWith('<!--', lt)) {
      final int close = html.indexOf('-->', lt + 4);
      if (close < 0) {
        at = lt + 4;
      } else {
        hidden.add((start: lt, end: close + 3));
        at = close + 3;
      }
      continue;
    }
    final Match? open = _rawTextOpen.matchAsPrefix(html, lt);
    if (open == null) {
      at = lt + 1;
      continue;
    }
    final int bodyStart = _openTagEnd(html, open.end);
    final String name = open.group(1)!;
    final RegExpMatch? close = RegExp(
      '</$name(?=[\\s/>])',
      caseSensitive: false,
    ).allMatches(html, bodyStart).firstOrNull;
    final int bodyEnd = close?.start ?? html.length;
    hidden.add((start: bodyStart, end: bodyEnd));
    if (name.toLowerCase() == 'script') {
      scripts.add((
        tagStart: lt,
        openTag: html.substring(lt, bodyStart),
        bodyStart: bodyStart,
        body: html.substring(bodyStart, bodyEnd),
      ));
    }
    at = bodyEnd;
  }
  return _Markup(hidden, scripts);
}

int _openTagEnd(String html, int from) {
  String? quote;
  for (var i = from; i < html.length; i++) {
    final String c = html[i];
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '>') {
      return i + 1;
    }
  }
  return html.length;
}

/// A manual bridge loader outside the generated block.
final class _ManualLoaderException extends WebSetupException {
  _ManualLoaderException(this.excerpt)
    : super(
        'index.html already loads the WebGPU bridge outside the generated '
        'llamadart block ("$excerpt"). Loading it twice wastes memory, and a '
        'failing old loader makes model loads fail. Remove that loader and '
        'rerun, or keep it and rerun with --no-index-html.',
      );

  final String excerpt;
}

void _rejectManualBridgeLoader(String htmlOutsideBlock) {
  final _Markup markup = _scanMarkup(htmlOutsideBlock);
  for (final _Script script in markup.scripts) {
    final int? at = _loaderOffset(script);
    if (at != null) {
      throw _ManualLoaderException(_excerpt(htmlOutsideBlock, at));
    }
  }
}

int? _loaderOffset(_Script script) {
  for (final RegExpMatch src in _srcAttribute.allMatches(script.openTag)) {
    final String value = src.group(1) ?? src.group(2) ?? src.group(3)!;
    if (_bridgeModule.hasMatch(value)) return script.tagStart + src.start;
  }
  final RegExpMatch? loader =
      _bridgeModuleImport.firstMatch(script.body) ??
      _bridgeGlobalAssignment.firstMatch(script.body);
  return loader == null ? null : script.bodyStart + loader.start;
}

String _excerpt(String html, int at) {
  final int lineStart = html.lastIndexOf('\n', at) + 1;
  final int lineEnd = html.indexOf('\n', at);
  final int end = lineEnd < 0 ? html.length : lineEnd;
  final int from = at - lineStart > _maxExcerptChars ~/ 2
      ? at - _maxExcerptChars ~/ 2
      : lineStart;
  final int to = end - from > _maxExcerptChars ? from + _maxExcerptChars : end;
  return '${from > lineStart ? '...' : ''}'
      '${html.substring(from, to).trim()}'
      '${to < end ? '...' : ''}';
}

String _indentedSnippet(WebBridgePin pin, String indent, String newline) {
  final String snippet = _bootstrapTemplate.replaceAll('{{TAG}}', pin.tag);
  return const LineSplitter()
      .convert(snippet)
      .map((String line) => line.isEmpty ? line : '$indent$line')
      .join(newline);
}

// The `v` query keeps browsers from reusing a previous release's cached files.
const String _bootstrapTemplate = r'''
<!-- llamadart:web_setup:begin -->
<!-- WebGPU bridge assets {{TAG}}. Generated by `dart run llamadart:web_setup`; rerun it instead of editing. -->
<script type="module">
  try {
    const base = new URL('webgpu_bridge/', document.baseURI);
    const asset = (name) => {
      const url = new URL(name, base);
      url.searchParams.set('v', '{{TAG}}');
      return url.href;
    };
    const mod = await import(asset('llama_webgpu_bridge.js'));
    if (typeof mod.LlamaWebGpuBridge !== 'function') {
      throw new Error('llama_webgpu_bridge.js does not export LlamaWebGpuBridge');
    }
    window.__llamadartBridgeCoreModuleUrl = asset('llama_webgpu_core.js');
    window.__llamadartBridgeWasmUrl = asset('llama_webgpu_core.wasm');
    window.__llamadartBridgeCoreModuleUrlMem64 = asset('llama_webgpu_core_mem64.js');
    window.__llamadartBridgeWasmUrlMem64 = asset('llama_webgpu_core_mem64.wasm');
    if (typeof mod.enableBridgeWorkerHost === 'function') {
      window.__llamadartBridgeWorkerUrl = asset('llama_webgpu_bridge_worker.js');
    }
    window.__llamadartBridgeSpeechToTextSupported ??= true;
    window.__llamadartBridgeAdaptiveSafariGpu =
      mod.LlamaWebGpuBridge.supportsSafariAdaptiveGpu === true;
    window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
  } catch (error) {
    window.__llamadartBridgeLoadError =
      `webgpu_bridge/ assets {{TAG}} failed to load; rerun dart run llamadart:web_setup and serve web/webgpu_bridge/ (${error})`;
  }
</script>
<!-- llamadart:web_setup:end -->''';

File _requireWebDir(Directory webDir, {required bool needIndexHtml}) {
  if (!webDir.existsSync()) {
    throw WebSetupException(
      '${webDir.path} does not exist. Run this from the app root of a '
      'Flutter Web app (flutter create --platforms web .), or pass --web-dir.',
    );
  }
  final File indexHtml = File(p.join(webDir.path, 'index.html'));
  if (needIndexHtml && !indexHtml.existsSync()) {
    throw WebSetupException(
      '${indexHtml.path} does not exist. Pass the directory that holds the '
      "app's index.html with --web-dir, or use --no-index-html.",
    );
  }
  return indexHtml;
}

String _readText(File file) {
  try {
    return file.readAsStringSync();
  } on FileSystemException catch (error) {
    throw WebSetupException('Cannot read ${file.path}: ${error.message}');
  } on FormatException {
    throw WebSetupException('${file.path} is not UTF-8 text.');
  }
}

List<int>? _readIfPinned(File manifestFile, WebBridgePin pin) {
  if (!manifestFile.existsSync()) return null;
  final List<int> bytes = manifestFile.readAsBytesSync();
  return sha256.convert(bytes).toString() == pin.manifestSha256 ? bytes : null;
}

final class _AssetDigest {
  const _AssetDigest(this.sha256Hex, this.sizeBytes);

  final String sha256Hex;
  final int sizeBytes;
}

Map<String, _AssetDigest> _parseManifest(List<int> bytes, WebBridgePin pin) {
  final String actual = sha256.convert(bytes).toString();
  if (actual != pin.manifestSha256) {
    throw WebSetupException(
      'The ${pin.tag} manifest has SHA-256 $actual, but this llamadart '
      'version trusts ${pin.manifestSha256}. Nothing was written. Retry; if '
      'it repeats, the CDN is serving different bytes, so do not use them and '
      'report it at https://github.com/leehack/llamadart/issues.',
    );
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw WebSetupException('The ${pin.tag} manifest is not JSON: $error');
  }
  final Object? files = json is Map<String, Object?> ? json['files'] : null;
  final Object? tag = json is Map<String, Object?> ? json['release_tag'] : null;
  if (files is! Map<String, Object?> || tag != pin.tag) {
    throw WebSetupException(
      'The ${pin.tag} manifest does not describe release ${pin.tag} files.',
    );
  }
  final digests = <String, _AssetDigest>{};
  for (final String name in webBridgeRuntimeFiles) {
    final Object? entry = files[name];
    final Object? hash = entry is Map<String, Object?> ? entry['sha256'] : null;
    final Object? size = entry is Map<String, Object?>
        ? entry['size_bytes']
        : null;
    if (hash is! String || !_sha256Hex.hasMatch(hash) || size is! int) {
      throw WebSetupException(
        'The ${pin.tag} manifest has no valid SHA-256 and size for $name.',
      );
    }
    digests[name] = _AssetDigest(hash, size);
  }
  return digests;
}

Future<bool> _matches(File file, _AssetDigest digest) async {
  if (!file.existsSync() || file.lengthSync() != digest.sizeBytes) {
    return false;
  }
  final Digest actual = await sha256.bind(file.openRead()).first;
  return actual.toString() == digest.sha256Hex;
}

Future<List<int>> _download(
  WebBridgeFetch fetch,
  Uri url, {
  required int maxBytes,
}) async {
  final bytes = <int>[];
  try {
    await for (final List<int> chunk in await fetch(url)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw WebSetupException('$url is larger than $maxBytes bytes.');
      }
    }
  } on Exception catch (error) {
    throw _downloadFailure(url, error);
  }
  return bytes;
}

Future<void> _downloadVerified(
  WebBridgeFetch fetch,
  Uri url,
  File target,
  _AssetDigest digest,
) async {
  final File partial = File('${target.path}.download');
  final hashSink = _DigestSink();
  final ByteConversionSink hasher = sha256.startChunkedConversion(hashSink);
  final IOSink out = partial.openWrite();
  var received = 0;
  try {
    await for (final List<int> chunk in await fetch(url)) {
      received += chunk.length;
      if (received > digest.sizeBytes) {
        throw WebSetupException(
          '$url is larger than the ${digest.sizeBytes} bytes its manifest '
          'lists. Nothing was replaced.',
        );
      }
      hasher.add(chunk);
      out.add(chunk);
    }
    await out.close();
    hasher.close();
    final String actual = hashSink.value.toString();
    if (received != digest.sizeBytes || actual != digest.sha256Hex) {
      throw WebSetupException(
        '$url has $received bytes with SHA-256 $actual, but its pinned '
        'manifest lists ${digest.sizeBytes} bytes with ${digest.sha256Hex}. '
        'Nothing was replaced. Retry; if it repeats, report it at '
        'https://github.com/leehack/llamadart/issues.',
      );
    }
    partial.renameSync(target.path);
  } on Exception catch (error) {
    await out.close().catchError((Object _) {});
    if (partial.existsSync()) partial.deleteSync();
    throw _downloadFailure(url, error);
  }
}

WebSetupException _downloadFailure(Uri url, Exception error) =>
    error is WebSetupException
    ? error
    : WebSetupException(
        'Cannot download $url: $error. Check the network connection and '
        'retry.',
      );

Future<Stream<List<int>>> _httpFetch(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final HttpClientResponse response = await (await client.getUrl(
      url,
    )).close();
    if (response.statusCode != HttpStatus.ok) {
      throw WebSetupException(
        'Cannot download $url: HTTP ${response.statusCode}.',
      );
    }
    return response
        .timeout(
          const Duration(seconds: 60),
          onTimeout: (EventSink<List<int>> sink) => sink.addError(
            WebSetupException('Download of $url stalled for 60 seconds.'),
          ),
        )
        .transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (EventSink<List<int>> sink) {
              client.close();
              sink.close();
            },
          ),
        );
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

void _writeAtomically(File file, List<int> bytes) {
  final File partial = File('${file.path}.tmp')..writeAsBytesSync(bytes);
  partial.renameSync(file.path);
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
