@TestOn('vm')
library;

import 'package:llamadart/src/backends/litert_lm/worker_messages.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('LiteRT-LM worker messages', () {
    test(
      'native settlement is independent of error kind and cancellation ack',
      () {
        for (final state in LiteRtLmNativeSettlement.values) {
          final error = LiteRtLmErrorResponse.from(
            LlamaModelException('native failure'),
            nativeSettlement: state,
          );
          expect(error.kind, 'llamaModel');
          expect(error.nativeSettlement, state);
          expect(
            LiteRtLmDoneResponse(nativeSettlement: state).nativeSettlement,
            state,
          );
        }
      },
    );

    test('maps Dart errors into worker error responses', () {
      expect(
        LiteRtLmErrorResponse.from(UnsupportedError('nope')).kind,
        'unsupported',
      );
      expect(LiteRtLmErrorResponse.from(ArgumentError('bad')).kind, 'argument');
      expect(LiteRtLmErrorResponse.from(StateError('wrong')).kind, 'state');
      final unsupported = LiteRtLmErrorResponse.from(
        LlamaUnsupportedException('no remote images'),
      );
      expect(unsupported.kind, 'llamaUnsupported');
      expect(unsupported.message, 'no remote images');

      final cases = <(LlamaException, String)>[
        (LlamaArgumentException('bad value'), 'llamaArgument'),
        (LlamaModelException('bad model', 'detail'), 'llamaModel'),
        (LlamaContextException('no context'), 'llamaContext'),
        (LlamaInferenceException('decode failed'), 'llamaInference'),
        (LlamaStateException('busy'), 'llamaState'),
      ];
      for (final (error, kind) in cases) {
        final response = LiteRtLmErrorResponse.from(error);
        expect(response.kind, kind);
        expect(response.message, isNot(contains('LlamaException:')));
      }
      expect(
        LiteRtLmErrorResponse.from(
          LlamaModelException('bad model', 'detail'),
        ).message,
        'bad model (detail)',
      );

      final named = LiteRtLmErrorResponse.from(
        LlamaArgumentException('bad value', name: 'prompt'),
      );
      expect(named.argumentName, 'prompt');
      expect(LiteRtLmErrorResponse.from(StateError('x')).argumentName, isNull);
      expect(
        LiteRtLmErrorResponse.from(LlamaArgumentException('bad')).argumentName,
        isNull,
      );

      final generic = LiteRtLmErrorResponse.from(Exception('native failed'));
      expect(generic.kind, 'exception');
      expect(generic.message, contains('native failed'));
    });
  });
}
