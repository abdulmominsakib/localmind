@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';

final _draft = ModelSource.path('draft.gguf');

GenerationParams _speculative(SpeculativeDecodingConfig config) =>
    GenerationParams(speculativeDecodingConfig: config);

Matcher _argumentError(String message, {String name = 'draftMicroBatchSize'}) =>
    throwsA(
      isA<LlamaArgumentException>()
          .having((error) => error.name, 'name', name)
          .having((error) => error.message, 'message', contains(message)),
    );

void main() {
  group('draftMicroBatchSize', () {
    final service = LlamaCppService();

    Object? resolve(SpeculativeDecodingConfig config) =>
        service.debugResolveSpeculativeNativeParamsForTesting(
          _speculative(config),
        )['draftMicroBatchSize'];

    test('reaches the native config of each draft-context strategy', () {
      for (final config in <SpeculativeDecodingConfig>[
        SpeculativeDecodingConfig.draftSimple(
          draftModel: _draft,
          draftMicroBatchSize: 8,
        ),
        SpeculativeDecodingConfig.draftEagle3(
          draftModel: _draft,
          draftMicroBatchSize: 8,
        ),
        const SpeculativeDecodingConfig.mtp(draftMicroBatchSize: 8),
        SpeculativeDecodingConfig.mixed(
          strategies: [
            SpeculativeDecodingStrategy.ngramMod,
            SpeculativeDecodingStrategy.draftSimple,
          ],
          draftModel: _draft,
          draftMicroBatchSize: 8,
        ),
      ]) {
        expect(resolve(config), 8, reason: '${config.effectiveStrategies}');
      }
      expect(
        resolve(SpeculativeDecodingConfig.draftSimple(draftModel: _draft)),
        isNull,
      );
    });

    test('rejects a value below one', () {
      for (final size in [0, -1]) {
        expect(
          () => resolve(
            SpeculativeDecodingConfig.draftSimple(
              draftModel: _draft,
              draftMicroBatchSize: size,
            ),
          ),
          _argumentError('must be at least 1'),
        );
      }
    });

    test('rejects n-gram strategies, which have no draft context', () {
      expect(
        () => resolve(
          const SpeculativeDecodingConfig.mixed(
            strategies: [
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.ngramSimple,
            ],
            draftMicroBatchSize: 8,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('creates no draft context'),
          ),
        ),
      );
    });

    test('needs a whole draft block for draft-dflash and draft-dspark', () {
      for (final strategy in [
        SpeculativeDecodingStrategy.draftDflash,
        SpeculativeDecodingStrategy.draftDspark,
      ]) {
        SpeculativeDecodingConfig config(int size) =>
            SpeculativeDecodingConfig.mixed(
              strategies: [strategy],
              draftModel: _draft,
              draftTokenMax: 4,
              draftMicroBatchSize: size,
            );

        expect(
          () => resolve(config(4)),
          _argumentError('at least draftTokenMax + 1 (5)'),
          reason: '$strategy',
        );
        expect(resolve(config(5)), 5, reason: '$strategy');
      }
      // The block holds the effective draft length, which a mixed n-gram
      // strategy can raise.
      expect(
        () => resolve(
          SpeculativeDecodingConfig.mixed(
            strategies: [
              SpeculativeDecodingStrategy.ngramSimple,
              SpeculativeDecodingStrategy.draftDflash,
            ],
            draftModel: _draft,
            draftTokenMax: 4,
            ngramSizeM: 16,
            draftMicroBatchSize: 5,
          ),
        ),
        _argumentError('(17)'),
      );
      expect(
        resolve(
          SpeculativeDecodingConfig.draftSimple(
            draftModel: _draft,
            draftTokenMax: 4,
            draftMicroBatchSize: 1,
          ),
        ),
        1,
      );
    });

    test('needs the whole trained block for a LiliCorr draft model', () {
      for (final strategy in [
        SpeculativeDecodingStrategy.draftDflash,
        SpeculativeDecodingStrategy.draftDspark,
      ]) {
        void validate(int size, Map<String, String> metadata) =>
            service.debugValidateDraftBlockMicroBatchForTesting(
              _speculative(
                SpeculativeDecodingConfig.mixed(
                  strategies: [strategy],
                  draftModel: _draft,
                  draftTokenMax: 4,
                  draftMicroBatchSize: size,
                ),
              ),
              draftMetadata: metadata,
            );

        const liliCorr = {
          'lilicorr.candidate_topk': '4',
          'dflash.block_size': '8',
        };
        expect(
          () => validate(7, liliCorr),
          _argumentError('dflash.block_size (8)'),
          reason: '$strategy',
        );
        expect(() => validate(8, liliCorr), returnsNormally);
        // llama.cpp's block size without the key.
        expect(
          () => validate(15, {'lilicorr.candidate_topk': '4'}),
          _argumentError('dflash.block_size (16)'),
          reason: '$strategy',
        );
        expect(
          () => validate(16, {'lilicorr.candidate_topk': '4'}),
          returnsNormally,
        );
        // Without LiliCorr the block is draftTokenMax + 1.
        for (final metadata in <Map<String, String>>[
          {},
          {'dflash.block_size': '8'},
          {'lilicorr.candidate_topk': '0', 'dflash.block_size': '8'},
        ]) {
          expect(
            () => validate(5, metadata),
            returnsNormally,
            reason: '$strategy $metadata',
          );
        }
      }
      // Other draft-model strategies do not decode a block.
      expect(
        () => service.debugValidateDraftBlockMicroBatchForTesting(
          _speculative(
            SpeculativeDecodingConfig.draftSimple(
              draftModel: _draft,
              draftMicroBatchSize: 1,
            ),
          ),
          draftMetadata: {
            'lilicorr.candidate_topk': '4',
            'dflash.block_size': '8',
          },
        ),
        returnsNormally,
      );
    });

    test('the inherited target micro-batch needs the block llama.cpp '
        'decodes', () {
      void validate(
        SpeculativeDecodingStrategy strategy, {
        required int microBatch,
        int batch = 64,
        int draftTokenMax = 4,
        bool mixedNgram = false,
        Map<String, String> metadata = const {},
      }) => service.debugValidateDraftBlockMicroBatchForTesting(
        _speculative(
          SpeculativeDecodingConfig.mixed(
            strategies: [
              if (mixedNgram) SpeculativeDecodingStrategy.ngramSimple,
              strategy,
            ],
            draftModel: _draft,
            draftTokenMax: draftTokenMax,
          ),
        ),
        draftMetadata: metadata,
        targetBatchSize: batch,
        targetMicroBatchSize: microBatch,
      );
      Matcher inherited(int size, int block) => _argumentError(
        'ModelParams.microBatchSize (resolved to $size; the draft context '
        'inherits it while SpeculativeDecodingConfig.draftMicroBatchSize is '
        'unset) must be at least the $block-token draft block',
        name: 'microBatchSize',
      );
      const dspark = SpeculativeDecodingStrategy.draftDspark;
      const dflash = SpeculativeDecodingStrategy.draftDflash;

      // Anchor-first DSpark (sample_from_anchor absent or "true") decodes
      // draftTokenMax tokens; Qwen3-8B DSpark ran with these on 0.16.0.
      for (final metadata in <Map<String, String>>[
        {},
        {'dflash.sample_from_anchor': 'true'},
      ]) {
        expect(
          () => validate(dspark, microBatch: 4, metadata: metadata),
          returnsNormally,
        );
        expect(
          () => validate(dspark, microBatch: 3, metadata: metadata),
          inherited(3, 4),
        );
      }
      expect(
        () => validate(dspark, microBatch: 8, draftTokenMax: 8),
        returnsNormally,
      );
      expect(
        () => validate(dspark, microBatch: 7, draftTokenMax: 8),
        inherited(7, 8),
      );
      // A mixed n-gram strategy raises draftTokenMax to ngramSizeM (48),
      // which llama.cpp clamps to the 16-token block.
      expect(
        () => validate(dspark, microBatch: 16, mixedNgram: true),
        returnsNormally,
      );
      expect(
        () => validate(dspark, microBatch: 15, mixedNgram: true),
        inherited(15, 16),
      );
      expect(
        () => validate(
          dspark,
          microBatch: 4,
          draftTokenMax: 8,
          metadata: {'dflash.block_size': '4'},
        ),
        returnsNormally,
      );
      expect(
        () => validate(
          dspark,
          microBatch: 3,
          draftTokenMax: 8,
          metadata: {'dflash.block_size': '4'},
        ),
        inherited(3, 4),
      );
      // Without anchor-first sampling DSpark, like DFlash, adds the anchor;
      // llama.cpp reads only the exact string "true" as true.
      for (final (strategy, metadata) in [
        (dspark, {'dflash.sample_from_anchor': 'false'}),
        (dspark, {'dflash.sample_from_anchor': '1'}),
        (dspark, {'dflash.sample_from_anchor': 'TRUE'}),
        (dflash, <String, String>{}),
        (dflash, {'dflash.sample_from_anchor': 'true'}),
      ]) {
        expect(
          () => validate(strategy, microBatch: 5, metadata: metadata),
          returnsNormally,
          reason: '$strategy $metadata',
        );
        expect(
          () => validate(strategy, microBatch: 4, metadata: metadata),
          inherited(4, 5),
          reason: '$strategy $metadata',
        );
      }
      expect(
        () => validate(dflash, microBatch: 16, mixedNgram: true),
        returnsNormally,
      );
      expect(
        () => validate(dflash, microBatch: 15, mixedNgram: true),
        inherited(15, 16),
      );

      // llama.cpp clamps n_ubatch to n_batch and takes n_batch for zero.
      expect(
        () => validate(dflash, batch: 4, microBatch: 512),
        inherited(4, 5),
      );
      expect(() => validate(dflash, batch: 4, microBatch: 0), inherited(4, 5));
      expect(() => validate(dflash, batch: 5, microBatch: 0), returnsNormally);

      const liliCorr = {'lilicorr.candidate_topk': '4'};
      for (final strategy in [dflash, dspark]) {
        expect(
          () => validate(strategy, microBatch: 15, metadata: liliCorr),
          _argumentError(
            'ModelParams.microBatchSize (resolved to 15; the draft context '
            'inherits it while SpeculativeDecodingConfig.draftMicroBatchSize '
            'is unset) must be at least the draft model block size '
            'dflash.block_size (16)',
            name: 'microBatchSize',
          ),
          reason: '$strategy',
        );
        expect(
          () => validate(strategy, microBatch: 16, metadata: liliCorr),
          returnsNormally,
        );
      }

      // The target context stores ModelParams resolved by the same helper.
      for (final (params, size) in [
        (const ModelParams(microBatchSize: 4), 4),
        (const ModelParams(batchSize: 4), 4),
      ]) {
        final target = LlamaCppService.resolveContextBatchSizes(params, 4096);
        expect(
          () => validate(
            dflash,
            batch: target.batchSize,
            microBatch: target.microBatchSize,
          ),
          inherited(size, 5),
        );
      }
      final defaults = LlamaCppService.resolveContextBatchSizes(
        const ModelParams(),
        4096,
      );
      expect(
        () => validate(
          dflash,
          batch: defaults.batchSize,
          microBatch: defaults.microBatchSize,
          metadata: liliCorr,
        ),
        returnsNormally,
      );

      // A set draftMicroBatchSize replaces the target's.
      expect(
        () => service.debugValidateDraftBlockMicroBatchForTesting(
          _speculative(
            SpeculativeDecodingConfig.draftDflash(
              draftModel: _draft,
              draftTokenMax: 4,
              draftMicroBatchSize: 16,
            ),
          ),
          draftMetadata: liliCorr,
          targetBatchSize: 64,
          targetMicroBatchSize: 1,
        ),
        returnsNormally,
      );
      // Other draft-model strategies do not decode a block.
      expect(
        () => validate(
          SpeculativeDecodingStrategy.draftSimple,
          microBatch: 1,
          metadata: liliCorr,
        ),
        returnsNormally,
      );
    });

    test("must fit the context's logical batch and context size", () {
      void validate(int? size, {required int batch, required int context}) =>
          service.debugValidateDraftMicroBatchSizeForTesting(
            _speculative(
              SpeculativeDecodingConfig.draftSimple(
                draftModel: _draft,
                draftMicroBatchSize: size,
              ),
            ),
            batchSize: batch,
            contextSize: context,
          );

      expect(() => validate(null, batch: 8, context: 8), returnsNormally);
      expect(() => validate(512, batch: 512, context: 2048), returnsNormally);
      expect(
        () => validate(513, batch: 512, context: 2048),
        _argumentError('logical batch size (512)'),
      );
      expect(
        () => validate(257, batch: 512, context: 256),
        _argumentError('logical batch size (256)'),
      );
    });
  });

  // A regression in the real runtime aborts at a GGML_ASSERT, so its suite
  // runs in a child process to fail this test rather than the whole runner.
  test('draft context runtime suite passes in a child process', () async {
    final suite = await compileDartScriptWithBundledNativeAssets(
      'test/fixtures/llama_cpp_draft_context_suite.dart',
    );
    final result = await Process.run(Platform.resolvedExecutable, [suite]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('All tests passed!'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
