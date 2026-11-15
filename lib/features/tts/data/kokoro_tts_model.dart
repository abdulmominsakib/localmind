import '../../../core/models/enums.dart';
import 'tts_bundle.dart';

/// sherpa-onnx `kokoro-int8-multi-lang-v1_1`: bilingual (zh + en) Kokoro-82M
/// int8 bundle, 103 speakers, espeak-ng-data phonemization with comma-joined
/// per-language lexicons and zh rule FSTs for date/number/phone reading.
class KokoroTtsModel implements TtsBundleDescriptor {
  const KokoroTtsModel();

  static const KokoroTtsModel instance = KokoroTtsModel();

  @override
  EngineId get engine => EngineId.kokoro;

  @override
  String get bundleDirName => 'kokoro-int8-multi-lang-v1_1';

  @override
  String get tarballUrl =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      '$bundleDirName.tar.bz2';

  // Nominal int8 bundle size (model ~82 MB + voices.bin 26 MB + espeak data);
  // the live progress bar prefers the server-reported total when present.
  @override
  int get totalSizeBytes => 115 * 1024 * 1024;

  @override
  String get modelFileName => 'model.int8';

  @override
  String get tokensFileName => 'tokens.txt';

  @override
  List<String> get requiredFileNames => [
    modelFileName,
    tokensFileName,
    'voices.bin',
    'lexicon-us-en.txt',
    'lexicon-zh.txt',
  ];

  @override
  List<String> get requiredDirNames => ['espeak-ng-data'];

  @override
  List<String> get ruleFstFileNames => [
    'date-zh.fst',
    'number-zh.fst',
    'phone-zh.fst',
  ];
}
