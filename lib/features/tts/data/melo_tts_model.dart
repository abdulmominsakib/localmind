import '../../../core/models/enums.dart';
import 'tts_bundle.dart';

/// sherpa-onnx `vits-melo-tts-zh_en`: bilingual (zh + en) single-speaker
/// VITS voice, phonemized through a lexicon plus the jieba dict directory.
///
/// File layout verified against the official `vits-melo-tts-zh_en.tar.bz2`
/// (167,006,755 bytes). The archive also carries a 133-byte placeholder
/// `model.int8.onnx` — deliberately not listed: the full-precision
/// `model.onnx` is the only usable model file in this bundle.
class MeloTtsModel implements TtsBundleDescriptor {
  const MeloTtsModel();

  static const MeloTtsModel instance = MeloTtsModel();

  @override
  EngineId get engine => EngineId.melo;

  @override
  String get bundleDirName => 'vits-melo-tts-zh_en';

  @override
  String get tarballUrl =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      '$bundleDirName.tar.bz2';

  @override
  int get totalSizeBytes => 167006755;

  @override
  String get modelFileName => 'model.onnx';

  @override
  String get tokensFileName => 'tokens.txt';

  @override
  List<String> get requiredFileNames => [
    modelFileName,
    tokensFileName,
    'lexicon.txt',
  ];

  @override
  List<String> get requiredDirNames => ['dict'];

  @override
  List<String> get ruleFstFileNames => [
    'date.fst',
    'number.fst',
    'phone.fst',
    'new_heteronym.fst',
  ];
}
