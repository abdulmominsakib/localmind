import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

const qwen3TokenizerFixture = 'qwen3-0.6b';
const qwen3UpdatedModelSha256 =
    'c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108';
const qwen3OriginalModelSha256 =
    '555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4';

/// Selects the opt-in vocabulary fixture; generic smokes run no Qwen probes.
String? selectLiteRtLmTokenizerFixture(String? value) {
  if (value == null || value.isEmpty) return null;
  if (value != qwen3TokenizerFixture) {
    throw ArgumentError.value(
      value,
      'LITERT_LM_TOKENIZER_FIXTURE',
      'Unknown tokenizer fixture',
    );
  }
  return value;
}

/// Binds the token IDs to the two known immutable Qwen3 vocabularies.
/// The original is admitted so the negative control reaches the decode check.
Future<String> verifyQwen3TokenizerArtifact(File model) async {
  final digest = (await sha256.bind(model.openRead()).first).toString();
  if (digest != qwen3UpdatedModelSha256 && digest != qwen3OriginalModelSha256) {
    throw StateError(
      'Qwen3 tokenizer fixture requires a known Qwen3-0.6B '
      'artifact; SHA-256 $digest does not match.',
    );
  }
  return digest;
}

/// Checks split-token fidelity separately from encode/decode round trips.
Future<Map<String, Object>> checkQwen3Tokenizer(LlamaEngine engine) async {
  const tokenIds = [9707, 0, 26525, 232];
  const expected = 'Hello! 😊';
  final decoded = await engine.detokenize(tokenIds);
  if (decoded != expected) {
    throw StateError(
      'Qwen3 split-token decode mismatch: expected "$expected", '
      'got "$decoded" for $tokenIds. Replace the legacy model artifact; '
      'do not rewrite literal user text.',
    );
  }
  const controls = ['Hello!', 'Hello! 😊', 'café 한글 日本語', 'ĠðŁĺĬ'];
  for (final text in controls) {
    final tokens = await engine.tokenize(text, addSpecial: false);
    final roundTrip = await engine.detokenize(tokens);
    if (roundTrip != text) {
      throw StateError(
        'Qwen3 tokenizer round-trip mismatch: '
        'expected "$text", got "$roundTrip".',
      );
    }
  }
  return {
    'tokenIds': tokenIds,
    'decoded': decoded,
    'roundTripControls': controls,
  };
}
