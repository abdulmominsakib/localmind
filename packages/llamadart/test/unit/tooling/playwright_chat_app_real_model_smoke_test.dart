@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/bounded_process.dart';

const _script = 'tool/testing/playwright_chat_app_real_model_smoke.py';
const _playwrightReached = 'fake playwright reached';

// Well above any run here: `python` stays under 4 s even on GitHub's Windows
// runners.
const _processTimeout = Duration(seconds: 60);

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => runBoundedProcess(
  executable,
  arguments,
  timeout: _processTimeout,
  environment: environment,
);

// Stands in for a browser: the page answers from a scenario and records the
// scripts the helper hands it.
const _scriptedPlaywright = r'''
import json
import os

_SCENARIO = json.loads(os.environ["LLAMADART_FAKE_PLAYWRIGHT_SCENARIO"])
_CAPTURE = {"initScript": None, "evaluateScripts": []}


def _save():
    with open(_SCENARIO["capturePath"], "w", encoding="utf-8") as capture:
        json.dump(_CAPTURE, capture)


class TimeoutError(Exception):
    pass


class _Anything:
    def __getattr__(self, name):
        return _Anything()

    def __call__(self, *args, **kwargs):
        return _Anything()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class _Request:
    method = "GET"
    failure = None

    def __init__(self, url):
        self.url = url


class _Body(_Anything):
    def inner_text(self, **kwargs):
        return _SCENARIO["body"]


class _Page(_Anything):
    def __init__(self):
        self._handlers = {}

    def add_init_script(self, script):
        _CAPTURE["initScript"] = script
        _save()

    def on(self, event, handler):
        self._handlers.setdefault(event, []).append(handler)

    def goto(self, url, **kwargs):
        for requested in _SCENARIO["requests"]:
            for handler in self._handlers.get("request", []):
                handler(_Request(requested))

    def locator(self, selector):
        return _Body() if selector == "body" else _Anything()

    def evaluate(self, script, *args):
        _CAPTURE["evaluateScripts"].append(script)
        _save()
        return _SCENARIO["pageState"]


class _Context(_Anything):
    def new_page(self):
        return _Page()


class _Browser(_Anything):
    def new_context(self, **kwargs):
        return _Context()


class _Chromium:
    def launch(self, **kwargs):
        return _Browser()


class _Playwright(_Anything):
    chromium = _Chromium()


def sync_playwright():
    return _Playwright()
''';

// Stands in for safaridriver: answers W3C WebDriver commands for one scripted
// chat-app page and logs each command for the test to inspect.
const _fakeSafariDriver = r'''#!/usr/bin/env python3
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SCENARIO = json.loads(os.environ['LLAMADART_FAKE_SAFARI_SCENARIO'])
ELEMENT = {'element-6066-11e4-a52e-4f735466cecf': 'node-1'}


if SCENARIO.get('stderrBytes'):
    sys.stderr.write('x' * SCENARIO['stderrBytes'])
    sys.stderr.flush()

with open(SCENARIO['logPath'] + '.pid', 'w', encoding='utf-8') as out:
    out.write(str(os.getpid()))


def log(entry):
    with open(SCENARIO['logPath'], 'a', encoding='utf-8') as out:
        out.write(json.dumps(entry) + '\n')


def execute(script, args):
    if 'requestAnimationFrame(tick)' in script:
        return {'visibility': SCENARIO['visibility'], 'frames': SCENARIO['frames']}
    if 'querySelectorAll(selector)' in script:
        return ELEMENT
    if 'document.body.innerText' in script:
        return 'Model loaded successfully! Ready to chat.'
    if 'liteRtLmResponse:' in script:
        return {'liteRtLmResponse': '4'}
    if "getEntriesByType('resource')" in script:
        return ['https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/+esm']
    return None


class Handler(BaseHTTPRequestHandler):
    def _reply(self, value):
        data = json.dumps({'value': value}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._reply({'ready': True})

    def do_DELETE(self):
        log({'method': 'DELETE', 'path': self.path})
        self._reply(None)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])) or b'{}')
        command = self.path.split('/')[-1]
        log({'method': 'POST', 'command': command, 'body': body})
        if self.path == '/session':
            self._reply({'sessionId': 's1', 'capabilities': {'browserVersion': '27.0'}})
        elif command == 'sync':
            self._reply(execute(body['script'], body['args']))
        else:
            self._reply(None)

    def log_message(self, *_):
        pass


HTTPServer(('127.0.0.1', int(sys.argv[sys.argv.index('-p') + 1])), Handler).serve_forever()
''';

// Runs the smoke helper with safari_webdriver pointed at the fake driver.
const _safariSmokeLauncher = r'''
import runpy
import sys

sys.path.insert(0, 'tool/testing')
import safari_webdriver

safari_webdriver.SAFARIDRIVER = sys.argv.pop(1)
sys.argv[0] = 'tool/testing/playwright_chat_app_real_model_smoke.py'
runpy.run_path(sys.argv[0], run_name='__main__')
''';

const _safariStartFailureProbe = r'''
import sys
import tempfile

sys.path.insert(0, 'tool/testing')
import safari_webdriver

opened = []
real = tempfile.TemporaryFile
safari_webdriver.tempfile.TemporaryFile = lambda *a, **k: opened.append(real(*a, **k)) or opened[-1]
safari_webdriver.SAFARIDRIVER = sys.argv[1]
try:
    safari_webdriver.SafariSession()
except OSError:
    pass
print(f'closed={opened[0].closed}')
''';

const _safariStartTimeoutProbe = r'''
import sys

sys.path.insert(0, 'tool/testing')
import safari_webdriver

safari_webdriver.SAFARIDRIVER = sys.argv[1]
safari_webdriver._DRIVER_START_TIMEOUT_S = 1
try:
    safari_webdriver.SafariSession()
except safari_webdriver.WebDriverError as error:
    print(error)
''';

// Runs the recorded page scripts against a stand-in `@litert-lm/core` module,
// loading the wrapped module the way `LiteRtLmBackend` does on the Web.
const _pageScriptHarness = r'''
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [failureCapturePath, successCapturePath, workDir] = process.argv.slice(2);
const failure = JSON.parse(readFileSync(failureCapturePath, 'utf8'));
const success = JSON.parse(readFileSync(successCapturePath, 'utf8'));
const evaluate = (script) => (0, eval)(`(${script})`)();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const runtimePath = join(workDir, 'fake_litert_lm.mjs');
writeFileSync(
  runtimePath,
  `export const Backend = {};
export class Engine {
  static calls = 0;
  static async create(settings) {
    Engine.calls += 1;
    if (settings.model === 'broken') {
      throw new Error('fake engine create failed');
    }
    return {
      async createConversation() {
        return {
          sendMessageStreaming() {
            return new ReadableStream({
              start(controller) {
                controller.enqueue({ content: [{ text: '4' }] });
                controller.close();
              },
            });
          },
        };
      },
    };
  }
}
`,
);
const runtimeUrl = pathToFileURL(runtimePath).href;

globalThis.window = globalThis;
Object.defineProperty(globalThis, 'localStorage', {
  configurable: true,
  value: { setItem() {}, removeItem() {} },
});
// Node cannot import a blob: URL, so the wrapper module goes through a file.
let wrapperSource;
URL.createObjectURL = (blob) => {
  wrapperSource = blob.text();
  return 'blob:llamadart-test';
};
window.__llamadartLiteRtLmModuleUrl = runtimeUrl;
(0, eval)(success.initScript);
// The init script polls for a WebGPU bridge that never loads here. Left
// running, its interval turns any stalled await below into a hang instead of
// node's unsettled top-level await error.
clearInterval(window.__llamadartRealBridgePatchTimer);

const wrapperPath = join(workDir, 'wrapped_litert_lm.mjs');
writeFileSync(wrapperPath, await wrapperSource);
const wrapper = await import(pathToFileURL(wrapperPath).href);
const runtime = await import(runtimeUrl);
const runtimeCreate = runtime.Engine.create;
window.LiteRtLmEngine = wrapper.Engine;
// Longer than any timer the init script could install before the app calls
// Engine.create.
await sleep(200);

const report = {
  runtimeUrl,
  runtimeCreateReplaced: runtime.Engine.create !== runtimeCreate,
};
try {
  const engine = await window.LiteRtLmEngine.create({ model: 'ok' });
  const conversation = await engine.createConversation({});
  const reader = conversation.sendMessageStreaming('2+2?').getReader();
  while (!(await reader.read()).done) {}
  for (let i = 0; i < 100 && !window.__llamadartRealLiteRtLmLastResponse; i++) {
    await sleep(20);
  }
  await window.LiteRtLmEngine.create({ model: 'ok' });
  report.runtimeCreateCalls = runtime.Engine.calls;
  report.response = window.__llamadartRealLiteRtLmLastResponse;
  report.prompt = window.__llamadartRealLiteRtLmLastPrompt;
  report.settingsModel = window.__llamadartRealLiteRtLmLastSettings.model;
  report.resultGlobals = evaluate(success.evaluateScripts.at(-1));
} catch (error) {
  report.createError = String(error);
}
try {
  await window.LiteRtLmEngine.create({ model: 'broken' });
} catch (error) {
  report.brokenCreateError = String(error);
}
report.loadFailureStates = failure.evaluateScripts.map(evaluate);
console.log(JSON.stringify(report));
process.exit(0);
''';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart-smoke-args-');
    final package = Directory(p.join(tempDir.path, 'playwright'));
    await package.create();
    await File(p.join(package.path, '__init__.py')).writeAsString('');
    await File(p.join(package.path, 'sync_api.py')).writeAsString(
      'class TimeoutError(Exception):\n'
      '    pass\n'
      '\n'
      'def sync_playwright():\n'
      '    raise SystemExit("$_playwrightReached")\n',
    );
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<ProcessResult> runSmoke(String audioName, {bool microphone = false}) {
    final audio = File(p.join(tempDir.path, audioName))
      ..writeAsBytesSync(const <int>[0]);
    return _runProcess(
      Platform.isWindows ? 'python' : 'python3',
      [
        _script,
        'http://127.0.0.1:1/',
        '--model-url',
        'http://127.0.0.1:1/model.gguf',
        '--mmproj-url',
        'http://127.0.0.1:1/mmproj.gguf',
        '--speech-audio-path',
        audio.path,
        if (microphone) '--speech-microphone',
        '--expect',
        'Known transcript.',
      ],
      environment: {'PYTHONPATH': tempDir.path},
    );
  }

  for (final name in ['speech.wav', 'speech.mp3', 'speech.FLAC']) {
    test('accepts a $name selected-file fixture', () async {
      final result = await runSmoke(name);

      expect(result.stderr, contains(_playwrightReached));
    });
  }

  test('rejects other selected-file encodings', () async {
    final result = await runSmoke('speech.ogg');

    expect(result.exitCode, 2);
    expect(
      result.stderr,
      contains('--speech-audio-path must be a WAV, MP3 or FLAC file'),
    );
  });

  test('requires a WAV for the fake microphone', () async {
    final result = await runSmoke('speech.mp3', microphone: true);

    expect(result.exitCode, 2);
    expect(
      result.stderr,
      contains('--speech-microphone requires a WAV --speech-audio-path'),
    );
  });

  test('rejects speech input in Safari', () async {
    final audio = File(p.join(tempDir.path, 'speech.wav'))
      ..writeAsBytesSync(const <int>[0]);
    final result = await _runProcess(
      Platform.isWindows ? 'python' : 'python3',
      [
        _script,
        'http://127.0.0.1:1/',
        '--model-url',
        'http://127.0.0.1:1/model.gguf',
        '--mmproj-url',
        'http://127.0.0.1:1/mmproj.gguf',
        '--speech-audio-path',
        audio.path,
        '--browser',
        'safari',
      ],
      environment: {'PYTHONPATH': tempDir.path},
    );

    expect(result.exitCode, 2);
    expect(
      result.stderr,
      contains('--browser safari supports plain chat only'),
    );
  });

  group(
    'Safari chat run against a scripted safaridriver',
    testOn: '!windows',
    // Two cold Python processes: the helper and the stand-in driver it starts.
    timeout: Timeout(_processTimeout * 2 + const Duration(seconds: 10)),
    () {
      Future<({ProcessResult result, List<Map<String, dynamic>> commands})>
      runSafari({
        required String visibility,
        required int frames,
        int stderrBytes = 0,
      }) async {
        final driver = File(p.join(tempDir.path, 'fake_safaridriver'))
          ..writeAsStringSync(_fakeSafariDriver);
        await Process.run('chmod', ['+x', driver.path]);
        final logPath = p.join(tempDir.path, 'safari_commands.jsonl');
        final result = await runBoundedProcess(
          'python3',
          [
            '-c',
            _safariSmokeLauncher,
            driver.path,
            'http://127.0.0.1:1/app/',
            '--model-url',
            'http://127.0.0.1:1/model.litertlm',
            '--prompt',
            '2+2?',
            '--response-source',
            'litert',
            '--load-timeout-ms',
            '4000',
            '--response-timeout-ms',
            '4000',
            '--browser',
            'safari',
          ],
          environment: {
            'PYTHONPATH': tempDir.path,
            'LLAMADART_FAKE_SAFARI_SCENARIO': jsonEncode({
              'logPath': logPath,
              'visibility': visibility,
              'frames': frames,
              'stderrBytes': stderrBytes,
            }),
          },
          timeout: _processTimeout * 2,
        );
        final log = File(logPath);
        return (
          result: result,
          commands: log.existsSync()
              ? [
                  for (final line in log.readAsLinesSync())
                    jsonDecode(line) as Map<String, dynamic>,
                ]
              : <Map<String, dynamic>>[],
        );
      }

      test('loads, sends the prompt and reports the LiteRT-LM reply', () async {
        final run = await runSafari(visibility: 'visible', frames: 60);

        expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
        final events = [
          for (final line in (run.result.stdout as String).split('\n'))
            if (line.startsWith('{')) jsonDecode(line) as Map<String, dynamic>,
        ];
        final result = events.singleWhere(
          (event) => event['event'] == 'result',
        );
        expect(result['ok'], isTrue);
        expect(result['bridgeResponse'], '4');
        expect(result['liteRtLmRuntimeRequests'], [
          'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/+esm',
        ]);
        final commands = run.commands.map((c) => c['command']).toList();
        expect(commands.where((c) => c == 'url'), hasLength(2));
        expect(commands.where((c) => c == 'click'), hasLength(3));
        final typed = run.commands
            .where((c) => c['command'] == 'actions')
            .expand(
              (c) => (c['body']['actions'] as List).single['actions'] as List,
            )
            .where((a) => a['type'] == 'keyDown')
            .map((a) => a['value'])
            .join();
        expect(typed, '2+2?');
        expect(run.commands.last['method'], 'DELETE');
      });

      for (final (name, visibility, frames) in [
        ('is hidden', 'hidden', 60),
        ('renders no frames', 'visible', 0),
      ]) {
        test('fails before loading when the page $name', () async {
          final run = await runSafari(visibility: visibility, frames: frames);

          expect(run.result.exitCode, isNot(0));
          expect(run.result.stderr, contains('Safari page is not visible'));
          expect(run.commands.where((c) => c['command'] == 'click'), isEmpty);
          expect(run.commands.last['method'], 'DELETE');
        });
      }

      test('stops the driver process on close', () async {
        await runSafari(visibility: 'visible', frames: 60);

        final pid = File(
          p.join(tempDir.path, 'safari_commands.jsonl.pid'),
        ).readAsStringSync();
        final probe = await Process.run('kill', ['-0', pid]);
        if (probe.exitCode == 0) {
          await Process.run('kill', ['-9', pid]);
        }
        expect(probe.exitCode, isNot(0), reason: 'driver $pid still running');
      });

      test('does not stall on a driver that fills its stderr', () async {
        final run = await runSafari(
          visibility: 'visible',
          frames: 60,
          stderrBytes: 1 << 20,
        );

        expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
      });

      test('closes the stderr file when the driver cannot start', () async {
        final result = await runBoundedProcess('python3', [
          '-c',
          _safariStartFailureProbe,
          p.join(tempDir.path, 'missing'),
        ], timeout: _processTimeout);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('closed=True'));
      });

      test('shows driver stderr when it never answers', () async {
        final driver = File(p.join(tempDir.path, 'silent_safaridriver'))
          ..writeAsStringSync(
            '#!/usr/bin/env python3\n'
            'import sys, time\n'
            'sys.stderr.write("driver says no\\n"); sys.stderr.flush()\n'
            'time.sleep(30)\n',
          );
        await Process.run('chmod', ['+x', driver.path]);
        final result = await runBoundedProcess('python3', [
          '-c',
          _safariStartTimeoutProbe,
          driver.path,
        ], timeout: _processTimeout);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('did not start within'));
        expect(result.stdout, contains('driver says no'));
      });
    },
  );

  group(
    'LiteRT-LM chat run against a scripted page',
    // A test here runs up to three processes, so a stalled one reports through
    // _processTimeout instead of the default 30 s test timeout.
    timeout: Timeout(_processTimeout * 3),
    () {
      const moduleUrl =
          'https://cdn.jsdelivr.net/npm/@litert-lm/core@9.9.9/+esm';
      const wasmLoaderUrl =
          'https://cdn.jsdelivr.net/npm/@litert-lm/core@9.9.9/wasm/litertlm_wasm_internal.js';
      const wasmUrl =
          'https://cdn.jsdelivr.net/npm/@litert-lm/core@9.9.9/wasm/litertlm_wasm_internal.wasm';
      const modelUrl = 'http://127.0.0.1:1/model.litertlm';
      const createErrorStack =
          'RangeError: Maximum call stack size exceeded\n    at Proxy.<anonymous>';

      setUp(() async {
        await File(
          p.join(tempDir.path, 'playwright', 'sync_api.py'),
        ).writeAsString(_scriptedPlaywright);
      });

      Future<({ProcessResult result, Map<String, dynamic> capture})> runChat(
        String name, {
        required String body,
        required Map<String, Object?> pageState,
      }) async {
        final capturePath = p.join(tempDir.path, '$name.json');
        final result = await _runProcess(
          Platform.isWindows ? 'python' : 'python3',
          [
            _script,
            'http://127.0.0.1:1/',
            '--model-url',
            modelUrl,
            '--response-source',
            'litert',
            '--load-timeout-ms',
            '4000',
          ],
          environment: {
            'PYTHONPATH': tempDir.path,
            'LLAMADART_FAKE_PLAYWRIGHT_SCENARIO': jsonEncode({
              'capturePath': capturePath,
              'body': body,
              'pageState': pageState,
              'requests': [
                modelUrl,
                moduleUrl,
                wasmLoaderUrl,
                wasmUrl,
                moduleUrl,
              ],
            }),
          },
        );
        return (
          result: result,
          capture:
              jsonDecode(File(capturePath).readAsStringSync())
                  as Map<String, dynamic>,
        );
      }

      Future<({ProcessResult result, Map<String, dynamic> capture})>
      runFailedLoad() => runChat(
        'failed_load',
        body: 'Model failed to load\nRangeError\nRetry\nChange model',
        pageState: {'liteRtLmCreateErrorStack': createErrorStack},
      );

      Future<({ProcessResult result, Map<String, dynamic> capture})>
      runLoadedChat() => runChat(
        'loaded_chat',
        body: 'Model loaded successfully! Ready to chat.',
        pageState: {'liteRtLmResponse': '4'},
      );

      Future<({ProcessResult result, Map<String, dynamic> capture})>
      runPenaltyCheck(
        String name,
        List<String> flags, {
        required Object? capabilities,
        required Object? options,
      }) async {
        final capturePath = p.join(tempDir.path, '$name.json');
        final result = await _runProcess(
          Platform.isWindows ? 'python' : 'python3',
          [
            _script,
            'http://127.0.0.1:1/',
            '--model-url',
            modelUrl,
            '--allow-any-response',
            '--load-timeout-ms',
            '4000',
            ...flags,
          ],
          environment: {
            'PYTHONPATH': tempDir.path,
            'LLAMADART_FAKE_PLAYWRIGHT_SCENARIO': jsonEncode({
              'capturePath': capturePath,
              'body': 'Model loaded successfully! Ready to chat.',
              'pageState': {
                'bridgeResponse': 'ok',
                'capabilities': capabilities,
                'options': options,
              },
              'requests': [modelUrl],
            }),
          },
        );
        return (
          result: result,
          capture:
              jsonDecode(File(capturePath).readAsStringSync())
                  as Map<String, dynamic>,
        );
      }

      test(
        'lazy grammar smoke requires both probe and applied options',
        () async {
          const validOptions = {
            'hasGrammar': true,
            'grammarLazy': true,
            'grammarTriggerCount': 1,
          };
          final passed = await runPenaltyCheck(
            'lazy_valid',
            ['--expect-lazy-grammar'],
            capabilities: {'lazyGrammar': true},
            options: validOptions,
          );
          expect(passed.result.exitCode, 0, reason: '${passed.result.stderr}');
          for (final options in [
            {...validOptions, 'hasGrammar': false},
            {...validOptions, 'grammarLazy': false},
            {...validOptions, 'grammarTriggerCount': 0},
          ]) {
            final failed = await runPenaltyCheck(
              'lazy_missing_option',
              ['--expect-lazy-grammar'],
              capabilities: {'lazyGrammar': true},
              options: options,
            );
            expect(failed.result.exitCode, isNot(0));
            expect(
              failed.result.stderr,
              contains('lazy grammar with triggers'),
            );
          }
          final unsupported = await runPenaltyCheck(
            'lazy_false_probe',
            ['--expect-lazy-grammar'],
            capabilities: {'lazyGrammar': 'true'},
            options: validOptions,
          );
          expect(unsupported.result.exitCode, isNot(0));
          expect(
            unsupported.result.stderr,
            contains('did not report lazyGrammar'),
          );
        },
      );

      group('penaltyPromptTokens checks', () {
        const probe = '--expect-penalty-prompt-tokens-probe';
        const option = '--expect-penalty-prompt-tokens-option';

        test('the probe flag passes when the probe reports true', () async {
          final run = await runPenaltyCheck(
            'probe_pass',
            [probe],
            capabilities: {'penaltyPromptTokens': true},
            options: {},
          );
          expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
        });

        for (final capabilities in <Object?>[
          {'penaltyPromptTokens': false},
          <String, Object?>{},
          null,
        ]) {
          test('the probe flag fails on $capabilities', () async {
            final run = await runPenaltyCheck(
              'probe_fail',
              [probe],
              capabilities: capabilities,
              options: {},
            );
            expect(run.result.exitCode, isNot(0));
            expect(
              run.result.stderr,
              contains('did not report penaltyPromptTokens: true'),
            );
          });
        }

        test('the absent option passes and fails', () async {
          final pass = await runPenaltyCheck(
            'absent_pass',
            [option, 'absent'],
            capabilities: null,
            options: {'penaltyPromptTokens': '<absent>'},
          );
          expect(pass.result.exitCode, 0, reason: '${pass.result.stderr}');

          final fail = await runPenaltyCheck(
            'absent_fail',
            [option, 'absent'],
            capabilities: null,
            options: {'penaltyPromptTokens': false},
          );
          expect(fail.result.exitCode, isNot(0));
          expect(
            fail.result.stderr,
            contains('Completion call carried penaltyPromptTokens'),
          );
        });

        test('the false option passes and fails', () async {
          final pass = await runPenaltyCheck(
            'false_pass',
            [option, 'false'],
            capabilities: null,
            options: {'penaltyPromptTokens': false},
          );
          expect(pass.result.exitCode, 0, reason: '${pass.result.stderr}');

          for (final carried in <Object?>['<absent>', true]) {
            final fail = await runPenaltyCheck(
              'false_fail',
              [option, 'false'],
              capabilities: null,
              options: {'penaltyPromptTokens': carried},
            );
            expect(fail.result.exitCode, isNot(0), reason: '$carried');
          }
        });

        test('the init script records the option and the probe', () async {
          final initScript =
              (await runPenaltyCheck(
                    'init',
                    const [],
                    capabilities: null,
                    options: {},
                  )).capture['initScript']
                  as String;
          expect(initScript, contains("'penaltyPromptTokens' in options"));
          expect(initScript, contains('getCompletionCapabilities'));
          expect(initScript, contains("'<absent>'"));
        });

        test(
          'the patched bridge records the option, its absence and the probe',
          testOn: '!windows',
          () async {
            final initScript =
                (await runPenaltyCheck(
                      'node_init',
                      const [],
                      capabilities: null,
                      options: {},
                    )).capture['initScript']
                    as String;
            final scriptFile = File(p.join(tempDir.path, 'init.js'))
              ..writeAsStringSync(initScript);
            final harness = File(p.join(tempDir.path, 'penalty_harness.mjs'))
              ..writeAsStringSync(r"""
import fs from 'node:fs';
globalThis.window = globalThis;
globalThis.localStorage = { setItem() {}, removeItem() {} };
class LlamaWebGpuBridge {
  async createCompletion() { return 'ok'; }
  getCompletionCapabilities() {
    return Promise.resolve({ penaltyPromptTokens: true });
  }
}
globalThis.LlamaWebGpuBridge = LlamaWebGpuBridge;
(0, eval)(fs.readFileSync(process.argv[2], 'utf8'));
await new Promise(resolve => setTimeout(resolve, 100));
const bridge = new LlamaWebGpuBridge();
await bridge.createCompletion('p', { penalty: 1.1 });
const absent = window.__llamadartRealBridgeLastOptions.penaltyPromptTokens;
await bridge.createCompletion('p', { penaltyPromptTokens: false });
const falseValue = window.__llamadartRealBridgeLastOptions.penaltyPromptTokens;
await bridge.createCompletion('p', { penaltyPromptTokens: true });
const trueValue = window.__llamadartRealBridgeLastOptions.penaltyPromptTokens;
await bridge.getCompletionCapabilities();
await new Promise(resolve => setTimeout(resolve, 20));
console.log(JSON.stringify({
  absent, falseValue, trueValue,
  capabilities: window.__llamadartRealBridgeCompletionCapabilities,
}));
process.exit(0);
""");
            final node = await _runProcess('node', [
              harness.path,
              scriptFile.path,
            ]);

            expect(node.exitCode, 0, reason: '${node.stderr}');
            expect(jsonDecode((node.stdout as String).trim()), {
              'absent': '<absent>',
              'falseValue': false,
              'trueValue': true,
              'capabilities': {'penaltyPromptTokens': true},
            });
          },
        );

        test('--tools seeds the tools setting and a declaration', () async {
          const emptyDeclarations = r'"flutter.tool_declarations": "\"[]\""';
          final off =
              (await runPenaltyCheck(
                    'tools_off',
                    const [],
                    capabilities: null,
                    options: {},
                  )).capture['initScript']
                  as String;
          expect(off, contains('"flutter.tools_enabled": "false"'));
          expect(off, contains(emptyDeclarations));

          final on =
              (await runPenaltyCheck(
                    'tools_on',
                    const ['--tools'],
                    capabilities: null,
                    options: {},
                  )).capture['initScript']
                  as String;
          expect(on, contains('"flutter.tools_enabled": "true"'));
          expect(on, contains(r'getWeather'));
          expect(on, isNot(contains(emptyDeclarations)));
        });
      });

      List<Map<String, dynamic>> events(ProcessResult result) => [
        for (final line in const LineSplitter().convert(
          result.stdout as String,
        ))
          jsonDecode(line) as Map<String, dynamic>,
      ];

      test(
        'a failed model load ends the run with the page error state',
        () async {
          final run = await runFailedLoad();

          expect(run.result.exitCode, 1);
          expect(
            run.result.stderr,
            allOf(
              contains('App entered error state while waiting for model load'),
              contains(jsonEncode(createErrorStack)),
              isNot(contains('Timed out waiting for model load')),
            ),
          );
        },
      );

      test('the result names the LiteRT-LM runtime files requested', () async {
        final run = await runLoadedChat();

        expect(run.result.exitCode, 0, reason: '${run.result.stderr}');
        final emitted = events(run.result);
        expect(
          [
            for (final event in emitted)
              if (event['event'] == 'litert_lm_runtime_request') event['url'],
          ],
          [moduleUrl, wasmLoaderUrl, wasmUrl],
        );
        final result = emitted.singleWhere(
          (event) => event['event'] == 'result',
        );
        expect(result['liteRtLmRuntimeRequests'], [
          moduleUrl,
          wasmLoaderUrl,
          wasmUrl,
        ]);
      });

      test('the init script wraps Engine.create once and leaves '
          'window.LiteRtLmEngine alone', () async {
        final initScript =
            (await runLoadedChat()).capture['initScript'] as String;

        expect('new Proxy(mod.Engine'.allMatches(initScript), hasLength(1));
        expect(initScript.contains('LiteRtLmEngine'), isFalse);
        expect(initScript.contains('.create ='), isFalse);
      });

      // The page scripts target a browser, so node on Linux and macOS covers
      // them. The first `node` start of a GitHub Windows job takes 3-42 s
      // (later ones under 1 s) and has stalled past two minutes.
      const nodeTestOn = '!windows';

      Future<Map<String, dynamic>> runPageScripts() async {
        await runFailedLoad();
        await runLoadedChat();
        final harness = File(p.join(tempDir.path, 'page_script_harness.mjs'))
          ..writeAsStringSync(_pageScriptHarness);
        final node = await _runProcess('node', [
          harness.path,
          p.join(tempDir.path, 'failed_load.json'),
          p.join(tempDir.path, 'loaded_chat.json'),
          tempDir.path,
        ]);

        expect(node.exitCode, 0, reason: '${node.stderr}');
        return jsonDecode((node.stdout as String).trim())
            as Map<String, dynamic>;
      }

      // Issue 970: a second wrapper assigned through the module's Proxy made
      // Engine.create call itself until the stack overflowed.
      test(
        'wrapped Engine.create reaches the runtime once per call',
        testOn: nodeTestOn,
        () async {
          final report = await runPageScripts();

          expect(report['createError'], isNull);
          expect(report['runtimeCreateReplaced'], isFalse);
          expect(report['runtimeCreateCalls'], 2);
          expect(report['settingsModel'], 'ok');
          expect(report['prompt'], '2+2?');
          expect(report['response'], '4');
          expect(
            (report['resultGlobals']
                as Map<String, dynamic>)['liteRtLmOriginalModuleUrl'],
            report['runtimeUrl'],
          );
        },
      );

      test(
        'a rejected Engine.create leaves its stack for the load-failure '
        'report',
        testOn: nodeTestOn,
        () async {
          final report = await runPageScripts();

          expect(
            report['brokenCreateError'],
            'Error: fake engine create failed',
          );
          final state =
              (report['loadFailureStates'] as List<dynamic>).single
                  as Map<String, dynamic>;
          expect(state['liteRtLmError'], 'Error: fake engine create failed');
          expect(
            state['liteRtLmCreateErrorStack'],
            allOf(
              startsWith('Error: fake engine create failed\n'),
              contains('fake_litert_lm.mjs'),
            ),
          );
        },
      );
    },
  );
}
