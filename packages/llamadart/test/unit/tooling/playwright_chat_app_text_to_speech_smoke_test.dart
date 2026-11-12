@TestOn('vm')
@Timeout(Duration(seconds: 75))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/bounded_process.dart';

// The fake loses fill() input as Flutter semantics can, but delivers keyboard
// events. Stop at the actual synthesis click; no browser or model is needed.
const _playwright = r'''
import json
import os

scenario = json.loads(os.environ["LLAMADART_TTS_SCENARIO"])
capture = {"text": "stale prompt", "keys": [], "polls": [], "fills": 0,
           "clicked": False, "elapsed": 0.0}

class TimeoutError(Exception):
    pass

class SynthesisReached(Exception):
    pass

class _Setup:
    def __getattr__(self, name):
        return _Setup()
    def __call__(self, *args, **kwargs):
        return self
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False

class _Keyboard:
    selected = False
    def press(self, key):
        capture["keys"].append(key)
        if key == ("Meta+A" if scenario["platform"] == "Darwin" else "Control+A"):
            self.selected = True
        elif key == "Backspace" and self.selected:
            capture["text"] = ""
    def type(self, text):
        capture["text"] += text

class _Textbox:
    @property
    def last(self):
        return self
    def click(self):
        pass
    def fill(self, text):
        capture["fills"] += 1

class _Button:
    def __init__(self, name):
        self.name = name
    def wait_for(self, **kwargs):
        pass
    def is_enabled(self, timeout):
        capture["polls"].append({"name": self.name, "timeout": timeout})
        if scenario.get("unrelatedError"):
            raise ValueError("unrelated page error")
        if self.name != scenario["button"]:
            return False
        if len(capture["polls"]) == 1:
            raise TimeoutError("semantics temporarily absent")
        return (not scenario.get("disabled", False)
                and len(capture["polls"]) >= 4
                and capture["text"] == scenario["prompt"])
    def click(self):
        if self.name == "Load Model":
            return
        if self.name == "Synthesize speech":
            capture["clicked"] = True
            raise SynthesisReached()
        raise AssertionError("unexpected click: " + self.name)

class _Body:
    def inner_text(self, **kwargs):
        return "Model loaded successfully! Ready to chat."

class Page(_Setup):
    keyboard = _Keyboard()
    def get_by_role(self, role, name=None):
        if role == "textbox":
            return _Textbox()
        if role == "button":
            return _Button(name)
        raise AssertionError("unexpected role: " + role)
    def locator(self, selector):
        return _Body() if selector == "body" else _Setup()

class _Context(_Setup):
    def new_page(self):
        return Page()

class _Browser(_Setup):
    def new_context(self, **kwargs):
        return _Context()

class _Chromium:
    def launch(self, **kwargs):
        return _Browser()

class _Playwright(_Setup):
    chromium = _Chromium()

def sync_playwright():
    return _Playwright()
''';

const _runner = r'''
import json
import sys
from types import SimpleNamespace
from playwright.sync_api import capture, scenario, Page, SynthesisReached
import playwright_chat_app_utils as utils

utils.platform.system = lambda: scenario["platform"]
def sleep(seconds):
    capture["elapsed"] += seconds
utils.time = SimpleNamespace(monotonic=lambda: capture["elapsed"], sleep=sleep)
try:
    if scenario["driver"]:
        import playwright_chat_app_text_to_speech_smoke as driver
        sys.argv = ["tts", "http://127.0.0.1:1/", "--model-url",
                    "http://127.0.0.1:1/model.gguf", "--mmproj-url",
                    "http://127.0.0.1:1/mmproj.gguf", "--prompt", scenario["prompt"]]
        driver.main()
    else:
        utils.enter_chat_prompt(Page(), scenario["prompt"], timeout_ms=200)
except SynthesisReached:
    pass
finally:
    with open(scenario["capturePath"], "w", encoding="utf-8") as output:
        json.dump(capture, output)
''';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart-tts-input-');
    final package = Directory(p.join(tempDir.path, 'playwright'));
    await package.create();
    await File(p.join(package.path, '__init__.py')).writeAsString('');
    await File(p.join(package.path, 'sync_api.py')).writeAsString(_playwright);
    await File(p.join(tempDir.path, 'runner.py')).writeAsString(_runner);
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<({ProcessResult result, Map<String, dynamic> capture})> run({
    bool driver = true,
    String platform = 'Darwin',
    bool disabled = false,
    bool unrelatedError = false,
  }) async {
    final capturePath = p.join(tempDir.path, 'capture.json');
    final result = await runBoundedProcess(
      Platform.isWindows ? 'python' : 'python3',
      [p.join(tempDir.path, 'runner.py')],
      timeout: const Duration(seconds: 60),
      environment: {
        'PYTHONPATH': [
          tempDir.path,
          p.absolute('tool/testing'),
        ].join(Platform.isWindows ? ';' : ':'),
        'PYTHONDONTWRITEBYTECODE': '1',
        'LLAMADART_TTS_SCENARIO': jsonEncode({
          'capturePath': capturePath,
          'driver': driver,
          'platform': platform,
          'disabled': disabled,
          'unrelatedError': unrelatedError,
          'button': driver ? 'Synthesize speech' : 'Send message',
          'prompt': 'Hello, exact TTS input!\nSecond line.',
        }),
      },
    );
    return (
      result: result,
      capture:
          jsonDecode(await File(capturePath).readAsString())
              as Map<String, dynamic>,
    );
  }

  for (final platform in ['Darwin', 'Windows']) {
    test('TTS driver uses keyboard input and waits on $platform', () async {
      final (:result, :capture) = await run(platform: platform);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(capture['text'], 'Hello, exact TTS input!\nSecond line.');
      expect(capture['fills'], 0);
      expect(capture['keys'], [
        platform == 'Darwin' ? 'Meta+A' : 'Control+A',
        'Backspace',
      ]);
      expect(capture['polls'], hasLength(4));
      expect(
        capture['polls'],
        everyElement({'name': 'Synthesize speech', 'timeout': 250}),
      );
      expect(capture['clicked'], isTrue);
    });
  }

  test(
    'TTS driver fails within its bound when synthesis stays disabled',
    () async {
      final (:result, :capture) = await run(disabled: true);

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('Timed out waiting for Synthesize speech button to enable'),
      );
      expect(capture['clicked'], isFalse);
      expect(capture['elapsed'], inInclusiveRange(30, 30.1));
      expect((capture['polls'] as List).length, inInclusiveRange(600, 601));
    },
  );

  test('default chat helper still waits for Send message', () async {
    final (:result, :capture) = await run(driver: false, platform: 'Windows');

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(capture['text'], 'Hello, exact TTS input!\nSecond line.');
    expect(capture['polls'], hasLength(4));
    expect(
      capture['polls'],
      everyElement({'name': 'Send message', 'timeout': 250}),
    );
    expect(capture['keys'], ['Control+A', 'Backspace']);
  });

  test('unrelated button errors propagate without retrying', () async {
    final (:result, :capture) = await run(unrelatedError: true);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('ValueError: unrelated page error'));
    expect(capture['polls'], hasLength(1));
    expect(capture['clicked'], isFalse);
    expect(capture['elapsed'], 0);
  });
}
