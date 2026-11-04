@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/run_local_e2e.dart';

void main() {
  group('run_local_e2e', () {
    test('documents generated ngram cache text default', () async {
      final result = await runLocalE2e(const ['--help'], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('--ngram-cache-build-text <txt>'));
      expect(result.stdout, contains('--ngram-token-max <n>'));
      expect(result.stdout, contains('--allow-any-response'));
      expect(
        result.stdout,
        contains('defaults to the resolved benchmark prompt'),
      );
    });

    test('lists local-only Dart, Flutter, and Web smoke scenarios', () async {
      final result = await runLocalE2e(const ['--list'], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('root-template-e2e'));
      expect(result.stdout, contains('qwen35-multimodal-macos-repro'));
      expect(result.stdout, contains('gguf-chat-features-smoke'));
      expect(result.stdout, contains('llama-cpp-speculative-benchmark'));
      expect(result.stdout, contains('llama-cpp-chat-template-smoke'));
      expect(result.stdout, contains('litert-lm-chat-features-smoke'));
      expect(result.stdout, contains('webgpu-multimodal-regression'));
      expect(result.stdout, contains('chat-app-model-cache'));
      expect(result.stdout, contains('chat-app-web-real-model-smoke'));
      expect(result.stdout, contains('chat-app-web-mock-smoke'));
      expect(result.stdout, contains('chat-app-web-litert-gemma4-smoke'));
      expect(result.stdout, contains('bridge-smoke'));
      expect(result.stdout, contains('Dart local-only'));
      expect(result.stdout, contains('Flutter device'));
      expect(result.stdout, contains('Web smoke'));
    });

    test(
      'dry-runs a Flutter device scenario with the requested device',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'chat-app-model-cache',
          '--device',
          'macos',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(result.stdout, contains('chat-app-model-cache'));
        expect(
          result.stdout,
          contains(
            'cd /repo/example/chat_app && flutter test --run-skipped '
            '-t local-only integration_test/model_cache_mmproj_e2e_test.dart '
            '-d macos',
          ),
        );
      },
    );

    test(
      'dry-runs Web real-model smoke with build, serve, and Playwright steps',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'chat-app-web-real-model-smoke',
          '--model-url',
          'http://127.0.0.1:7358/models/tiny.gguf',
          '--expect',
          'ok',
          '--allow-any-response',
          '--python',
          '/custom/python',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(result.stdout, contains('scripts/build_chat_app_web.sh'));
        expect(
          result.stdout,
          contains(
            'CHAT_APP_BASE_HREF=/example/chat_app/build/web/ '
            'bash scripts/build_chat_app_web.sh',
          ),
        );
        expect(result.stdout, contains('serve_static_with_headers.py'));
        expect(
          result.stdout,
          contains('playwright_chat_app_real_model_smoke.py'),
        );
        expect(
          result.stdout,
          contains(
            '/custom/python tool/testing/playwright_chat_app_real_model_smoke.py',
          ),
        );
        expect(
          result.stdout,
          contains('--model-url http://127.0.0.1:7358/models/tiny.gguf'),
        );
        expect(result.stdout, contains('--expect ok'));
        expect(result.stdout, contains('--allow-any-response'));
      },
    );

    test(
      'dry-runs Web mock smoke with build, serve, and Playwright steps',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'chat-app-web-mock-smoke',
          '--model-url',
          'https://example.com/custom-mock.gguf',
          '--python',
          '/custom/python',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(result.stdout, contains('scripts/build_chat_app_web.sh'));
        expect(result.stdout, contains('serve_static_with_headers.py'));
        expect(result.stdout, contains('playwright_chat_app_mock_smoke.py'));
        expect(
          result.stdout,
          contains(
            '/custom/python tool/testing/playwright_chat_app_mock_smoke.py',
          ),
        );
        expect(
          result.stdout,
          contains(
            'http://127.0.0.1:7358/example/chat_app/build/web/?llamadart_mock_bridge=echo',
          ),
        );
        expect(
          result.stdout,
          contains('--model-url https://example.com/custom-mock.gguf'),
        );
      },
    );

    test('prefers repo-local Playwright Python by default', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'run_local_e2e_python_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final pythonPath = Platform.isWindows
          ? '${tempDir.path}/.dart_tool/playwright-python/Scripts/python.exe'
          : '${tempDir.path}/.dart_tool/playwright-python/bin/python';
      await File(pythonPath).create(recursive: true);

      final result = await runLocalE2e([
        '--scenario',
        'chat-app-web-litert-gemma4-smoke',
        '--skip-build',
        '--dry-run',
      ], projectRoot: tempDir.path);

      expect(result.exitCode, 0);
      expect(result.stdout, contains(pythonPath));
      expect(
        result.stdout,
        contains('bash scripts/validate_chat_app_web_build.sh'),
      );
      expect(
        result.stdout,
        contains('tool/testing/playwright_chat_app_real_model_smoke.py'),
      );
    });

    test(
      'dry-runs GGUF chat feature smoke with model path and backend',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'gguf-chat-features-smoke',
          '--model-path',
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
          '--backend',
          'cpu',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(result.stdout, contains('gguf-chat-features-smoke'));
        expect(
          result.stdout,
          contains(
            'cd /repo && dart run tool/gguf_chat_features_smoke.dart '
            'models/Qwen3.5-0.8B-Q4_K_M.gguf cpu',
          ),
        );
      },
    );

    test('dry-runs GGUF chat feature smoke with multimodal inputs', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'gguf-chat-features-smoke',
        '--model-path',
        'models/Qwen3.5-0.8B-Q4_K_M.gguf',
        '--backend',
        'cpu',
        '--mmproj-path',
        'models/Qwen3.5-0.8B-mmproj-F16.gguf',
        '--image-path',
        'test/fixtures/image.png',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo && dart run tool/gguf_chat_features_smoke.dart '
          'models/Qwen3.5-0.8B-Q4_K_M.gguf cpu '
          'models/Qwen3.5-0.8B-mmproj-F16.gguf test/fixtures/image.png',
        ),
      );
    });

    test('requires mmproj path before GGUF image path', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'gguf-chat-features-smoke',
        '--model-path',
        'models/Qwen3.5-0.8B-Q4_K_M.gguf',
        '--image-path',
        'test/fixtures/image.png',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--image-path requires --mmproj-path'));
    });

    test(
      'dry-runs llama.cpp speculative benchmark with matrix options',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'llama-cpp-speculative-benchmark',
          '--model-path',
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
          '--backend',
          'cpu',
          '--speculative-cases',
          'baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,mixed-ngram',
          '--benchmark-max-tokens',
          '128',
          '--benchmark-runs',
          '3',
          '--draft-token-max',
          '1,2',
          '--ngram-size-m',
          '8,16',
          '--ngram-token-max',
          '64',
          '--benchmark-warmups',
          '1',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(result.stdout, contains('llama-cpp-speculative-benchmark'));
        expect(
          result.stdout,
          contains(
            'cd /repo && dart run '
            'tool/testing/llama_cpp_speculative_benchmark.dart '
            '--model models/Qwen3.5-0.8B-Q4_K_M.gguf '
            '--cases baseline,ngram-simple,ngram-map-k,ngram-map-k4v,'
            'ngram-mod,mixed-ngram --backend cpu --gpu-layers 0 '
            '--max-tokens 128 --runs 3 --draft-token-max 1,2 --warmups 1 '
            '--ngram-size-m 8,16 --ngram-token-max 64',
          ),
        );
      },
    );

    test('dry-runs llama.cpp speculative benchmark with draft model', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'llama-cpp-speculative-benchmark',
        '--model-path',
        'models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        '--draft-model-path',
        'models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
        '--speculative-cases',
        'baseline,draft-simple,mixed-ngram-draft-simple',
        '--benchmark-max-tokens',
        '16',
        '--benchmark-runs',
        '1',
        '--draft-token-max',
        '1',
        '--benchmark-warmups',
        '0',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo && dart run '
          'tool/testing/llama_cpp_speculative_benchmark.dart '
          '--model models/qwen2.5-1.5b-instruct-q4_k_m.gguf '
          '--cases baseline,draft-simple,mixed-ngram-draft-simple '
          '--backend auto --gpu-layers 0 --max-tokens 16 --runs 1 '
          '--draft-token-max 1 --warmups 0 '
          '--draft-model models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
        ),
      );
    });

    test(
      'dry-runs llama.cpp speculative benchmark with generated ngram cache',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'llama-cpp-speculative-benchmark',
          '--model-path',
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
          '--speculative-cases',
          'baseline,ngram-cache',
          '--ngram-cache-build-static-path',
          '/tmp/llamadart-ngram-cache.bin',
          '--ngram-cache-build-text',
          'alpha beta gamma alpha beta delta',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            '--cases baseline,ngram-cache --backend auto --gpu-layers 0 '
            '--max-tokens 128 --runs 3 --draft-token-max 1,2 --warmups 1 '
            '--ngram-cache-build-static-path '
            '/tmp/llamadart-ngram-cache.bin --ngram-cache-build-text '
            "'alpha beta gamma alpha beta delta'",
          ),
        );
      },
    );

    test('requires model path for llama.cpp speculative benchmark', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'llama-cpp-speculative-benchmark',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains(
          '--model-path is required for llama-cpp-speculative-benchmark',
        ),
      );
    });

    test('dry-runs llama.cpp chat-template smoke with model path', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'llama-cpp-chat-template-smoke',
        '--model-path',
        'models/Qwen3.5-0.8B-Q4_K_M.gguf',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('llama-cpp-chat-template-smoke'));
      expect(
        result.stdout,
        contains(
          'LLAMADART_LLAMA_CPP_TEMPLATE_MODEL_PATH='
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
        ),
      );
      expect(
        result.stdout,
        contains(
          'dart test --run-skipped -t local-only '
          'test/e2e/backends/llama_cpp_chat_template_backend_e2e_test.dart',
        ),
      );
    });

    test('requires model path for llama.cpp chat-template smoke', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'llama-cpp-chat-template-smoke',
      ], projectRoot: '/repo');

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('--model-path is required for llama-cpp-chat-template-smoke'),
      );
    });

    test('requires model path for LiteRT-LM chat feature smoke', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'litert-lm-chat-features-smoke',
      ], projectRoot: '/repo');

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('--model-path is required for litert-lm-chat-features-smoke'),
      );
    });

    test('dry-runs LiteRT-LM chat feature smoke with model path', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'litert-lm-chat-features-smoke',
        '--model-path',
        'models/gemma-4-E2B-it.litertlm',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('litert-lm-chat-features-smoke'));
      expect(
        result.stdout,
        contains(
          'cd /repo && dart run tool/litert_lm_chat_features_smoke.dart '
          'models/gemma-4-E2B-it.litertlm auto',
        ),
      );
    });

    test(
      'dry-runs Web LiteRT-LM Gemma 4 smoke with LiteRT response capture',
      () async {
        final result = await runLocalE2e(const [
          '--scenario',
          'chat-app-web-litert-gemma4-smoke',
          '--skip-build',
          '--dry-run',
        ], projectRoot: '/repo');

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains('playwright_chat_app_real_model_smoke.py'),
        );
        expect(
          result.stdout,
          contains('gemma-4-E2B-it-web.litertlm?download=true'),
        );
        expect(result.stdout, contains('--response-source litert'));
        expect(result.stdout, contains('--backend-index 2'));
        expect(result.stdout, contains('--gpu-layers 999'));
        expect(result.stdout, contains('--penalty 1.1'));
      },
    );

    test('dry-runs WebGPU regression with forwarded runner options', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'webgpu-multimodal-regression',
        '--port',
        '9123',
        '--python',
        '/custom/python',
        '--skip-build',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('PLAYWRIGHT_GATE_PORT=9123'));
      expect(result.stdout, contains('PLAYWRIGHT_PYTHON=/custom/python'));
      expect(result.stdout, contains('LLAMADART_SKIP_WEB_BUILD=1'));
      expect(
        result.stdout,
        contains('bash tool/testing/run_webgpu_multimodal_regression_gate.sh'),
      );
    });

    test('reports unknown scenarios without executing anything', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'does-not-exist',
        '--dry-run',
      ], projectRoot: '/repo');

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('Unknown local E2E scenario: does-not-exist'),
      );
      expect(result.stderr, contains('Use --list'));
    });

    test('reports port conflicts before starting Web smoke servers', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socket.close);

      final result = await runLocalE2e([
        '--scenario',
        'bridge-smoke',
        '--port',
        '${socket.port}',
      ], projectRoot: '/repo');

      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('Running local E2E scenario: bridge-smoke'),
      );
      expect(result.stderr, contains('Port ${socket.port} is already in use'));
    });

    test('reports background server startup failures', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();

      final tempDir = await Directory.systemTemp.createTemp(
        'run_local_e2e_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await Directory(
        '${tempDir.path}/example/chat_app/web',
      ).create(recursive: true);

      final result = await runLocalE2e([
        '--scenario',
        'bridge-smoke',
        '--python',
        'dart',
        '--port',
        '$port',
      ], projectRoot: tempDir.path);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Background server exited'));
    });
  });
}
