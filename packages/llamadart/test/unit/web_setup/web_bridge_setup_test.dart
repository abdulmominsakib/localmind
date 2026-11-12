@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:llamadart/src/web_setup/web_bridge_setup.dart';

const String _flutterIndexHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>app</title>
</head>
<body>
  <!--
    You can customize the "flutter_bootstrap.js" script.
  -->
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

final class _FakeRelease {
  _FakeRelease({String tag = 'v9.9.9', Map<String, List<int>>? files})
    : files =
          files ??
          <String, List<int>>{
            for (final String name in webBridgeRuntimeFiles)
              name: utf8.encode('contents of $name for $tag'),
          } {
    manifestBytes = utf8.encode(
      jsonEncode(<String, Object?>{
        'release_tag': tag,
        'files': <String, Object?>{
          for (final MapEntry<String, List<int>> file in this.files.entries)
            file.key: <String, Object?>{
              'sha256': sha256.convert(file.value).toString(),
              'size_bytes': file.value.length,
            },
        },
      }),
    );
    pin = WebBridgePin(
      repository: 'example/assets',
      tag: tag,
      manifestSha256: sha256.convert(manifestBytes).toString(),
    );
  }

  final Map<String, List<int>> files;
  late final List<int> manifestBytes;
  late final WebBridgePin pin;

  /// Bodies served instead of the published bytes, keyed by file name.
  final Map<String, List<int>> served = <String, List<int>>{};
  final List<String> requests = <String>[];
  final List<Uri> urls = <Uri>[];

  Future<Stream<List<int>>> fetch(Uri url) async {
    final String name = url.pathSegments.last;
    urls.add(url);
    requests.add(name);
    final List<int>? body =
        served[name] ?? (name == 'manifest.json' ? manifestBytes : files[name]);
    if (body == null) throw const HttpException('404');
    return Stream<List<int>>.fromIterable(<List<int>>[
      body.sublist(0, body.length ~/ 2),
      body.sublist(body.length ~/ 2),
    ]);
  }
}

const String _manualLoaderHtml = '''
<!DOCTYPE html>
<html>
<head>
</head>
<body>
  <script type="module">
    try {
      const base = new URL('webgpu_bridge/', document.baseURI);
      const mod = await import(new URL('llama_webgpu_bridge.js', base).href);
      window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
    } catch (error) {
      window.__llamadartBridgeLoadError = String(error);
    }
  </script>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

/// Flips the first byte of [file], keeping its size.
void _corruptKeepingSize(File file) {
  final List<int> bytes = file.readAsBytesSync();
  bytes[0] ^= 0xff;
  file.writeAsBytesSync(bytes);
}

void main() {
  late Directory tempDir;
  late Directory webDir;
  late File indexHtml;
  late _FakeRelease release;

  String assetPath(String name) =>
      p.join(webDir.path, webBridgeAssetsDirName, name);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('web_bridge_setup_');
    webDir = Directory(p.join(tempDir.path, 'web'))..createSync();
    indexHtml = File(p.join(webDir.path, 'index.html'))
      ..writeAsStringSync(_flutterIndexHtml);
    release = _FakeRelease();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<WebSetupResult> runSetup({bool patchIndexHtml = true}) =>
      setUpWebBridge(
        webDir: webDir,
        pin: release.pin,
        fetch: release.fetch,
        patchIndexHtml: patchIndexHtml,
      );

  test('vendors every verified asset and adds the bootstrap once', () async {
    final WebSetupResult result = await runSetup();

    expect(result.downloaded, webBridgeRuntimeFiles);
    expect(result.unchanged, isEmpty);
    expect(result.indexHtmlUpdated, isTrue);
    expect(release.urls, <Uri>[
      for (final String name in <String>[
        'manifest.json',
        ...webBridgeRuntimeFiles,
      ])
        Uri.parse('https://cdn.jsdelivr.net/gh/example/assets@v9.9.9/$name'),
    ]);
    for (final String name in webBridgeRuntimeFiles) {
      expect(File(assetPath(name)).readAsBytesSync(), release.files[name]);
    }
    expect(
      File(assetPath('manifest.json')).readAsBytesSync(),
      release.manifestBytes,
    );
    final String html = indexHtml.readAsStringSync();
    expect(
      html.indexOf("searchParams.set('v', 'v9.9.9')"),
      allOf(
        greaterThan(html.indexOf('</head>')),
        lessThan(html.indexOf('<script src="flutter_bootstrap.js"')),
      ),
    );
    expect(html, contains("import(asset('llama_webgpu_bridge.js'))"));
    expect(html, contains('window.__llamadartBridgeLoadError ='));
    expect(
      Directory(
        p.join(webDir.path, webBridgeAssetsDirName),
      ).listSync().map((FileSystemEntity e) => p.basename(e.path)),
      unorderedEquals(<String>[...webBridgeRuntimeFiles, 'manifest.json']),
    );
  });

  test('a rerun fetches nothing and leaves index.html untouched', () async {
    await runSetup();
    final String html = indexHtml.readAsStringSync();
    final DateTime modified = indexHtml.lastModifiedSync();
    release.requests.clear();

    final WebSetupResult result = await runSetup();

    expect(release.requests, isEmpty);
    expect(result.downloaded, isEmpty);
    expect(result.unchanged, webBridgeRuntimeFiles);
    expect(result.indexHtmlUpdated, isFalse);
    expect(indexHtml.readAsStringSync(), html);
    expect(indexHtml.lastModifiedSync(), modified);
  });

  test('re-fetches only a file that no longer matches', () async {
    await runSetup();
    File(assetPath('llama_webgpu_core.js')).writeAsStringSync('edited');
    release.requests.clear();

    final WebSetupResult result = await runSetup();

    expect(release.requests, <String>['llama_webgpu_core.js']);
    expect(result.downloaded, <String>['llama_webgpu_core.js']);
    expect(
      File(assetPath('llama_webgpu_core.js')).readAsBytesSync(),
      release.files['llama_webgpu_core.js'],
    );
  });

  test('re-fetches an asset changed without changing its size', () async {
    await runSetup();
    final File core = File(assetPath('llama_webgpu_core.wasm'));
    _corruptKeepingSize(core);
    release.requests.clear();

    final WebSetupResult result = await runSetup();

    expect(release.requests, <String>['llama_webgpu_core.wasm']);
    expect(result.downloaded, <String>['llama_webgpu_core.wasm']);
    expect(core.readAsBytesSync(), release.files['llama_webgpu_core.wasm']);
  });

  test(
    're-fetches a local manifest changed without changing its size',
    () async {
      await runSetup();
      final File manifest = File(assetPath('manifest.json'));
      _corruptKeepingSize(manifest);
      release.requests.clear();

      final WebSetupResult result = await runSetup();

      expect(release.requests, <String>['manifest.json']);
      expect(result.downloaded, isEmpty);
      expect(manifest.readAsBytesSync(), release.manifestBytes);
    },
  );

  test(
    'rejects a served manifest of the pinned size but other bytes',
    () async {
      final List<int> forged = List<int>.of(release.manifestBytes);
      forged[forged.length - 2] ^= 0x01;
      release.served['manifest.json'] = forged;

      await expectLater(runSetup(), throwsA(isA<WebSetupException>()));
      expect(Directory(assetPath('')).listSync(), isEmpty);
    },
  );

  test(
    'refuses a page that already loads the bridge before downloading',
    () async {
      indexHtml.writeAsStringSync(_manualLoaderHtml);

      await expectLater(
        runSetup(),
        throwsA(
          isA<WebSetupException>().having(
            (WebSetupException e) => e.message,
            'message',
            allOf(
              contains("import(new URL('llama_webgpu_bridge.js', base).href)"),
              contains('Remove that loader'),
              contains('--no-index-html'),
            ),
          ),
        ),
      );
      expect(release.requests, isEmpty);
      expect(indexHtml.readAsStringSync(), _manualLoaderHtml);

      final WebSetupResult kept = await runSetup(patchIndexHtml: false);
      expect(kept.downloaded, webBridgeRuntimeFiles);
      expect(indexHtml.readAsStringSync(), _manualLoaderHtml);
    },
  );

  test('rejects a manifest whose bytes differ from the pin', () async {
    release.served['manifest.json'] = <int>[...release.manifestBytes, 0x20];

    await expectLater(
      runSetup(),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          allOf(contains(release.pin.manifestSha256), contains('v9.9.9')),
        ),
      ),
    );
    expect(release.requests, <String>['manifest.json']);
    expect(Directory(assetPath('')).listSync(), isEmpty);
    expect(indexHtml.readAsStringSync(), _flutterIndexHtml);
  });

  test('a tampered asset never replaces the existing file', () async {
    await runSetup();
    final File core = File(assetPath('llama_webgpu_core.wasm'))
      ..writeAsStringSync('stale');
    final List<int> published = release.files['llama_webgpu_core.wasm']!;
    release.served['llama_webgpu_core.wasm'] = <int>[
      ...published.sublist(1),
      0,
    ];

    await expectLater(
      runSetup(),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          allOf(contains('llama_webgpu_core.wasm'), contains('SHA-256')),
        ),
      ),
    );
    expect(core.readAsStringSync(), 'stale');
    expect(File('${core.path}.download').existsSync(), isFalse);
  });

  test('stops reading an asset larger than its manifest size', () async {
    final List<int> published = release.files['llama_webgpu_bridge.js']!;
    release.served['llama_webgpu_bridge.js'] = <int>[...published, 1, 2, 3];

    await expectLater(
      runSetup(),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          contains('larger than the ${published.length} bytes'),
        ),
      ),
    );
    expect(File(assetPath('llama_webgpu_bridge.js')).existsSync(), isFalse);
    expect(
      File(assetPath('llama_webgpu_bridge.js.download')).existsSync(),
      isFalse,
    );
  });

  test('reports a transport failure with the URL', () async {
    final WebBridgePin pin = release.pin;
    Future<Stream<List<int>>> failing(Uri url) =>
        Future<Stream<List<int>>>.error(const SocketException('offline'));

    await expectLater(
      setUpWebBridge(webDir: webDir, pin: pin, fetch: failing),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          allOf(contains('${pin.baseUri}manifest.json'), contains('offline')),
        ),
      ),
    );
  });

  test('rejects a manifest for another release or missing a file', () async {
    final _FakeRelease mislabeled = _FakeRelease(tag: 'v1.0.0');
    final WebBridgePin claimed = WebBridgePin(
      repository: mislabeled.pin.repository,
      tag: 'v9.9.9',
      manifestSha256: mislabeled.pin.manifestSha256,
    );
    await expectLater(
      setUpWebBridge(webDir: webDir, pin: claimed, fetch: mislabeled.fetch),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          contains('does not describe release v9.9.9'),
        ),
      ),
    );

    final _FakeRelease partial = _FakeRelease(
      files: <String, List<int>>{
        'llama_webgpu_bridge.js': <int>[1],
      },
    );
    await expectLater(
      setUpWebBridge(webDir: webDir, pin: partial.pin, fetch: partial.fetch),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          contains('llama_webgpu_bridge_worker.js'),
        ),
      ),
    );
  });

  test('requires the web directory and, unless skipped, index.html', () async {
    webDir.deleteSync(recursive: true);
    await expectLater(
      runSetup(),
      throwsA(
        isA<WebSetupException>().having(
          (WebSetupException e) => e.message,
          'message',
          contains('--web-dir'),
        ),
      ),
    );

    webDir.createSync();
    await expectLater(runSetup(), throwsA(isA<WebSetupException>()));

    final WebSetupResult result = await runSetup(patchIndexHtml: false);
    expect(result.downloaded, webBridgeRuntimeFiles);
    expect(result.indexHtmlUpdated, isFalse);
    expect(indexHtml.existsSync(), isFalse);
  });

  group('checkWebBridgeSetup', () {
    Future<List<String>> check({bool checkIndexHtml = true}) =>
        checkWebBridgeSetup(
          webDir: webDir,
          pin: release.pin,
          checkIndexHtml: checkIndexHtml,
        );

    test('passes after setup without any network access', () async {
      await runSetup();
      expect(await check(), isEmpty);
    });

    test('names the missing manifest of a fresh app', () async {
      expect(await check(), <Matcher>[
        allOf(contains('manifest.json'), contains('v9.9.9')),
      ]);
    });

    test('names each missing or changed asset and a stale index', () async {
      await runSetup();
      File(assetPath('llama_webgpu_core.js')).deleteSync();
      File(assetPath('llama_webgpu_core_mem64.wasm')).writeAsStringSync('x');
      indexHtml.writeAsStringSync(_flutterIndexHtml);

      expect(await check(), <Matcher>[
        allOf(contains('llama_webgpu_core.js'), contains('missing')),
        allOf(contains('llama_webgpu_core_mem64.wasm'), contains('match')),
        contains('index.html'),
      ]);
      expect(await check(checkIndexHtml: false), hasLength(2));
    });

    test('names assets and a manifest changed in place', () async {
      await runSetup();
      _corruptKeepingSize(File(assetPath('llama_webgpu_bridge.js')));

      expect(await check(), <Matcher>[
        allOf(contains('llama_webgpu_bridge.js'), contains('match')),
      ]);

      _corruptKeepingSize(File(assetPath('manifest.json')));
      expect(await check(), <Matcher>[contains('manifest.json')]);
    });

    test('reports a page that also loads the bridge by hand', () async {
      await runSetup();
      indexHtml.writeAsStringSync(
        indexHtml.readAsStringSync().replaceFirst(
          '</body>',
          '<script>window.LlamaWebGpuBridge = window.Other;</script>\n</body>',
        ),
      );

      final List<String> problems = await check();

      expect(problems, hasLength(1));
      expect(problems.single, contains('window.LlamaWebGpuBridge'));
      expect(problems.single, contains('Remove that loader'));
      expect(problems.single, contains('--no-index-html'));
      expect(problems.single, isNot(contains('web_setup')));
      expect('index.html'.allMatches(problems.single), hasLength(1));
    });

    test('quotes only a short excerpt of a single-line page', () async {
      await runSetup();
      indexHtml.writeAsStringSync(
        '<head>${'<meta name="x">' * 40}<script src="llama_webgpu_bridge.js">'
        '</script></head>',
      );

      final String problem = (await check()).single;

      expect(problem, startsWith(indexHtml.path));
      final String diagnostic = problem.substring(indexHtml.path.length);
      expect(diagnostic, contains('llama_webgpu_bridge.js'));
      expect(diagnostic, contains('...'));
      expect(diagnostic.length, lessThan(300));
    });
  });

  group('patchWebBridgeIndexHtml', () {
    test('replaces the block of an earlier release in place', () {
      final String older = patchWebBridgeIndexHtml(
        _flutterIndexHtml,
        _FakeRelease(tag: 'v1.0.0').pin,
      );

      final String upgraded = patchWebBridgeIndexHtml(older, release.pin);

      expect(upgraded, isNot(contains('v1.0.0')));
      expect(upgraded, patchWebBridgeIndexHtml(_flutterIndexHtml, release.pin));
    });

    test('falls back to </head> and keeps CRLF line endings', () {
      const String html = '<html>\r\n<head>\r\n</head>\r\n<body></body>\r\n';

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(
        patched.indexOf('<script type="module">'),
        lessThan(patched.indexOf('</head>')),
      );
      expect(patched.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(patchWebBridgeIndexHtml(patched, release.pin), patched);
    });

    test('keeps markup before the begin marker exactly once', () {
      final String generated = patchWebBridgeIndexHtml(
        '<head>\n</head>\n',
        release.pin,
      );
      final String block = generated.substring(
        generated.indexOf('<!-- llamadart:web_setup:begin -->'),
        generated.indexOf('</head>'),
      );
      final String html =
          '<html>\n  <head><meta charset="UTF-8">${block.trimRight()}\n'
          '  </head>\n</html>\n';

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(
        RegExp('<meta charset="UTF-8">').allMatches(patched),
        hasLength(1),
      );
      expect(patched, startsWith('<html>\n  <head><meta charset="UTF-8">\n'));
      expect(
        RegExp('llamadart:web_setup:begin').allMatches(patched),
        hasLength(1),
      );
      expect(patchWebBridgeIndexHtml(patched, release.pin), patched);
    });

    test('ignores a flutter_bootstrap.js script inside a comment', () {
      const String html =
          '<html>\n<head>\n</head>\n<body>\n  <!--\n'
          '  <script src="flutter_bootstrap.js" async></script>\n  -->\n'
          '  <script src="main.dart.js"></script>\n</body>\n</html>\n';

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(
        patched.indexOf('<script type="module">'),
        lessThan(patched.indexOf('</head>')),
      );
      expect(
        patched.substring(patched.indexOf('</head>')),
        html.substring(html.indexOf('</head>')),
      );
    });

    test('ignores a bridge loader that is commented out', () {
      final String html = _manualLoaderHtml
          .replaceFirst(
            '  <script type="module">',
            '  <!--\n  <script type="module">',
          )
          .replaceFirst(
            '  </script>\n  <script src',
            '  </script>\n  -->\n  <script src',
          );

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(patched, contains('llamadart:web_setup:begin'));
      expect(
        () => patchWebBridgeIndexHtml(_manualLoaderHtml, release.pin),
        throwsA(isA<WebSetupException>()),
      );
    });

    test('treats <!-- inside a script or style as text', () {
      const String html =
          '<html>\n<head>\n  <script>var a = "<!--";</script>\n'
          '  <style>/* <!-- */</style>\n</head>\n<body>\n'
          '  <script src="flutter_bootstrap.js" async></script>\n'
          '</body>\n</html>\n';

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(
        patched.indexOf('llamadart:web_setup:begin'),
        greaterThan(patched.indexOf('</style>')),
      );
      expect(
        patched.indexOf('llamadart:web_setup:begin'),
        lessThan(patched.indexOf('flutter_bootstrap.js')),
      );
      expect(patchWebBridgeIndexHtml(patched, release.pin), patched);
    });

    test('still finds a loader after a script that holds <!--', () {
      const String html =
          '<head>\n<script>var a = "<!--";</script>\n'
          '<script src="webgpu_bridge/llama_webgpu_bridge.js"></script>\n'
          '</head>\n';

      expect(
        () => patchWebBridgeIndexHtml(html, release.pin),
        throwsA(isA<WebSetupException>()),
      );
    });

    test('an unclosed comment does not hide the rest of the page', () {
      const String html =
          '<html>\n<head>\n</head>\n<body>\n  <!-- never closed\n'
          '  <script src="flutter_bootstrap.js" async></script>\n'
          '</body>\n</html>\n';

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(
        patched.indexOf('llamadart:web_setup:begin'),
        lessThan(patched.indexOf('flutter_bootstrap.js')),
      );
      expect(
        patched.indexOf('llamadart:web_setup:begin'),
        greaterThan(patched.indexOf('never closed')),
      );
    });

    test('skips a commented </head> for the real one', () {
      const String html =
          '<html>\n<head>\n<!--\n</head>\n-->\n<title>t</title>\n</head>\n'
          '<body></body>\n</html>\n';

      final String patched = patchWebBridgeIndexHtml(html, release.pin);

      expect(
        patched.indexOf('llamadart:web_setup:begin'),
        greaterThan(patched.indexOf('<title>')),
      );
      expect(
        patched.indexOf('llamadart:web_setup:begin'),
        lessThan(patched.lastIndexOf('</head>')),
      );
    });

    test('accepts mentions that do not load the bridge', () {
      for (final String markup in <String>[
        '<link rel="modulepreload" href="webgpu_bridge/llama_webgpu_bridge.js">',
        '<p>Uses llama_webgpu_bridge.js for WebGPU.</p>',
        '<script>const f = LlamaWebGpuBridge => 1;</script>',
        '<script>if (LlamaWebGpuBridge == null) {}</script>',
        '<script>if (LlamaWebGpuBridge === null) {}</script>',
        '<script>window.LlamaWebGpuBridge === undefined;</script>',
        '<script src="app_llama_webgpu_bridge_worker.js"></script>',
      ]) {
        final String html = '<head>\n$markup\n</head>\n';

        expect(
          patchWebBridgeIndexHtml(html, release.pin),
          contains('llamadart:web_setup:begin'),
          reason: markup,
        );
      }
    });

    test('refuses each real way of loading the bridge by hand', () {
      for (final String markup in <String>[
        '<script src="webgpu_bridge/llama_webgpu_bridge.js"></script>',
        "<script type=module src='llama_webgpu_bridge.js?v=1'></script>",
        '<script type="module">import "./llama_webgpu_bridge.js";</script>',
        '<script type="module">const m = await import("llama_webgpu_bridge.js");'
            '</script>',
        '<script>LlamaWebGpuBridge = window.Other;</script>',
        '<script>window.LlamaWebGpuBridge = window.Other;</script>',
        '<script>window["LlamaWebGpuBridge"] = window.Other;</script>',
        "<script>globalThis['LlamaWebGpuBridge']=window.Other;</script>",
      ]) {
        expect(
          () => patchWebBridgeIndexHtml(
            '<head>\n$markup\n</head>\n',
            release.pin,
          ),
          throwsA(isA<WebSetupException>()),
          reason: markup,
        );
      }
    });

    test('keeps a byte order mark before the begin marker', () {
      final String generated = patchWebBridgeIndexHtml(
        '<head>\n</head>\n',
        release.pin,
      );
      final String block = generated
          .substring(
            generated.indexOf('<!-- llamadart:web_setup:begin -->'),
            generated.indexOf('</head>'),
          )
          .trimRight();
      final String html = '\uFEFF$block\n</head>\n';

      expect(patchWebBridgeIndexHtml(html, release.pin), html);

      final String withMarkup = '\uFEFF<meta charset="UTF-8">$block\n</head>\n';
      final String patched = patchWebBridgeIndexHtml(withMarkup, release.pin);
      expect(patched, startsWith('\uFEFF<meta charset="UTF-8">\n'));
      expect(patchWebBridgeIndexHtml(patched, release.pin), patched);
    });

    test('refuses a page with no anchor or unbalanced markers', () {
      expect(
        () => patchWebBridgeIndexHtml('<body></body>', release.pin),
        throwsA(isA<WebSetupException>()),
      );
      expect(
        () => patchWebBridgeIndexHtml(
          '<head><!-- llamadart:web_setup:begin --></head>',
          release.pin,
        ),
        throwsA(isA<WebSetupException>()),
      );
    });
  });

  test(
    'vendors the pinned release from the CDN',
    () async {
      final WebSetupResult result = await setUpWebBridge(webDir: webDir);

      expect(result.downloaded, webBridgeRuntimeFiles);
      expect(await checkWebBridgeSetup(webDir: webDir), isEmpty);
    },
    tags: <String>['local-only'],
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
