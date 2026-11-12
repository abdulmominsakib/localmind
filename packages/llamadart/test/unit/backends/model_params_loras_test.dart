import 'package:llamadart/src/backends/model_params_loras.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:test/test.dart';

void main() {
  group('applyModelParamsLoras', () {
    late List<Object> calls;

    Future<void> run(
      List<LoraAdapterConfig> loras, {
      Object? failWith,
      String failOn = 'bad.gguf',
      Object? rollbackError,
    }) {
      return applyModelParamsLoras(
        loras,
        apply: (lora) async {
          calls.add((lora.path, lora.scale));
          if (failWith != null && lora.path == failOn) throw failWith;
        },
        rollback: () async {
          calls.add('rollback');
          if (rollbackError != null) throw rollbackError;
        },
      );
    }

    setUp(() => calls = <Object>[]);

    test('applies every adapter in order at its scale', () async {
      await run(const [
        LoraAdapterConfig(path: 'style.gguf', scale: 0.5),
        LoraAdapterConfig(path: 'domain.gguf'),
      ]);

      expect(calls, [('style.gguf', 0.5), ('domain.gguf', 1.0)]);
    });

    test('does nothing without adapters', () async {
      await run(const []);

      expect(calls, isEmpty);
    });

    test('rolls back, stops and names the adapter on a failure', () async {
      await expectLater(
        run(const [
          LoraAdapterConfig(path: 'ok.gguf'),
          LoraAdapterConfig(path: 'bad.gguf', scale: 0.3),
          LoraAdapterConfig(path: 'never.gguf'),
        ], failWith: LlamaModelException('Failed to load LoRA at bad.gguf')),
        throwsA(
          isA<LlamaModelException>()
              .having(
                (error) => error.message,
                'message',
                'Failed to apply the ModelParams.loras adapter bad.gguf',
              )
              .having(
                (error) => '${error.details}',
                'details',
                contains('Failed to load LoRA at bad.gguf'),
              ),
        ),
      );
      expect(calls, [('ok.gguf', 1.0), ('bad.gguf', 0.3), 'rollback']);
    });

    test('keeps unsupported failures typed', () async {
      for (final failure in <Object>[
        LlamaUnsupportedException('aLoRA adapter'),
        UnsupportedError('aLoRA adapter'),
      ]) {
        calls.clear();
        await expectLater(
          run(const [LoraAdapterConfig(path: 'bad.gguf')], failWith: failure),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              'Cannot apply the ModelParams.loras adapter bad.gguf: '
                  'aLoRA adapter',
            ),
          ),
        );
        expect(calls.last, 'rollback');
      }
    });

    test('reports the adapter failure when the rollback fails too', () async {
      await expectLater(
        run(
          const [LoraAdapterConfig(path: 'bad.gguf')],
          failWith: Exception('load failed'),
          rollbackError: StateError('rollback failed'),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => '${error.details}',
            'details',
            contains('load failed'),
          ),
        ),
      );
    });

    test('redacts URL secrets of the adapter', () async {
      const signed = 'https://example.com/bad.gguf?token=secret';
      await expectLater(
        run(
          const [LoraAdapterConfig(path: signed)],
          failOn: signed,
          failWith: Exception('could not fetch $signed'),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.toString(),
            'toString',
            allOf(contains('example.com/bad.gguf'), isNot(contains('secret'))),
          ),
        ),
      );
    });
  });
}
