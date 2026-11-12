@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

const _modelKey = 'LITERT_LM_MODEL';

/// A native `.litertlm` bundle takes media without a multimodal projector, so
/// this checks that `supportsVision` and `supportsAudio` read the runtime's
/// direct media support, as `capabilities` does. Set `LITERT_LM_MODEL` to a
/// bundle that declares vision or audio, such as Gemma 4 E2B.
void main() {
  final model = Platform.environment[_modelKey];

  test(
    'supportsVision and supportsAudio agree with capabilities on a .litertlm '
    'bundle',
    () async {
      final engine = LlamaEngine(LlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel(model!);

      final capabilities = await engine.capabilities;

      expect(engine.runtime, LlamaRuntime.liteRtLm);
      expect(engine.hasMultimodalProjector, isFalse);
      expect(
        capabilities.supportsVision || capabilities.supportsAudio,
        isTrue,
        reason: '$_modelKey must name a bundle that declares vision or audio.',
      );
      expect(await engine.supportsVision, capabilities.supportsVision);
      expect(await engine.supportsAudio, capabilities.supportsAudio);
    },
    skip: model != null && File(model).existsSync()
        ? false
        : 'Set $_modelKey to a .litertlm bundle with vision or audio.',
  );
}
