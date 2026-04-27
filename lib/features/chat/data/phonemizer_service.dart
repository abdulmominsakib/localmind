/// A basic English grapheme-to-phoneme (G2P) converter.
///
/// Converts English text into IPA-style phonemes suitable for KittenTTS.
/// This is a rule-based approach and is not perfect — it handles common
/// English pronunciation patterns. For production-grade accuracy, eSpeak
/// or a neural G2P model should be used instead.
class PhonemizerService {
  static final Map<String, String> _consonants = {
    'b': 'b', 'c': 'k', 'd': 'd', 'f': 'f', 'g': 'g',
    'h': 'h', 'j': 'dʒ', 'k': 'k', 'l': 'l', 'm': 'm',
    'n': 'n', 'p': 'p', 'q': 'k', 'r': 'ɹ', 's': 's',
    't': 't', 'v': 'v', 'w': 'w', 'x': 'ks', 'y': 'j',
    'z': 'z',
    // Common digraphs
    'ch': 'tʃ', 'sh': 'ʃ', 'th': 'θ', 'gh': '', 'ph': 'f',
    'wh': 'w', 'ng': 'ŋ', 'qu': 'kw', 'ck': 'k',
  };

  static final Map<String, String> _vowelRules = {
    'a': 'æ',   // cat
    'e': 'ɛ',   // bed
    'i': 'ɪ',   // sit
    'o': 'ɒ',   // hot (BrE)
    'u': 'ʌ',   // cup
    // Long vowels / diphthongs
    'ay': 'eɪ', 'ai': 'eɪ',
    'ee': 'iː', 'ea': 'iː',
    'ie': 'iː',
    'oa': 'oʊ', 'ow': 'oʊ',
    'oo': 'uː',
    'ue': 'uː',
    'ou': 'aʊ',
    'oi': 'ɔɪ', 'oy': 'ɔɪ',
    'au': 'ɔː',
    'aw': 'ɔː',
    'ar': 'ɑː',
    'er': 'ɜː',
    'ir': 'ɜː',
    'or': 'ɔː',
    'ur': 'ɜː',
    'igh': 'aɪ',
  };

  /// Convert English text to phonemized string for KittenTTS.
  ///
  /// Handles basic cleaning, punctuation removal, and rule-based phonemization.
  /// Words are separated by spaces.
  String phonemize(String text) {
    final cleaned = text
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    final words = cleaned.split(' ');
    final phonemizedWords = <String>[];

    for (final word in words) {
      if (word.isEmpty) continue;
      final phonemes = _phonemizeWord(word);
      phonemizedWords.add(phonemes);
    }

    return phonemizedWords.join(' ');
  }

  String _phonemizeWord(String word) {
    // Handle very common words first
    if (_commonWords.containsKey(word)) {
      return _commonWords[word]!;
    }

    final buffer = StringBuffer();
    int i = 0;

    while (i < word.length) {
      // Try digraphs first
      if (i < word.length - 1) {
        final two = word.substring(i, i + 2);
        final three = i < word.length - 2 ? word.substring(i, i + 3) : null;

        if (three != null && _vowelRules.containsKey(three)) {
          buffer.write(_vowelRules[three]);
          i += 3;
          continue;
        }

        if (_vowelRules.containsKey(two)) {
          buffer.write(_vowelRules[two]);
          i += 2;
          continue;
        }

        if (_consonants.containsKey(two)) {
          buffer.write(_consonants[two]);
          i += 2;
          continue;
        }
      }

      // Single letter
      final char = word[i];
      if (_vowelRules.containsKey(char)) {
        buffer.write(_vowelRules[char]);
      } else if (_consonants.containsKey(char)) {
        buffer.write(_consonants[char]);
      }
      i++;
    }

    return buffer.toString();
  }

  static final Map<String, String> _commonWords = {
    'the': 'ðə',
    'a': 'ə',
    'an': 'æn',
    'and': 'ænd',
    'of': 'ɒv',
    'to': 'tuː',
    'in': 'ɪn',
    'is': 'ɪz',
    'you': 'juː',
    'that': 'ðæt',
    'it': 'ɪt',
    'he': 'hiː',
    'was': 'wɒz',
    'for': 'fɔː',
    'on': 'ɒn',
    'are': 'ɑː',
    'as': 'æz',
    'with': 'wɪð',
    'his': 'hɪz',
    'they': 'ðeɪ',
    'at': 'æt',
    'be': 'biː',
    'this': 'ðɪs',
    'have': 'hæv',
    'from': 'frɒm',
    'or': 'ɔː',
    'one': 'wʌn',
    'had': 'hæd',
    'by': 'baɪ',
    'word': 'wɜːd',
    'but': 'bʌt',
    'not': 'nɒt',
    'what': 'wɒt',
    'all': 'ɔːl',
    'were': 'wɜː',
    'we': 'wiː',
    'when': 'wen',
    'your': 'jɔː',
    'can': 'kæn',
    'said': 'sed',
    'there': 'ðeə',
    'use': 'juːz',
    'each': 'iːtʃ',
    'which': 'wɪtʃ',
    'she': 'ʃiː',
    'do': 'duː',
    'how': 'haʊ',
    'their': 'ðeə',
    'if': 'ɪf',
    'will': 'wɪl',
    'up': 'ʌp',
    'other': 'ʌðə',
    'about': 'əbaʊt',
    'out': 'aʊt',
    'many': 'meni',
    'then': 'ðen',
    'them': 'ðem',
    'these': 'ðiːz',
    'so': 'səʊ',
    'some': 'sʌm',
    'her': 'hɜː',
    'would': 'wʊd',
    'make': 'meɪk',
    'like': 'laɪk',
    'into': 'ɪntuː',
    'him': 'hɪm',
    'has': 'hæz',
    'two': 'tuː',
    'more': 'mɔː',
    'go': 'gəʊ',
    'way': 'weɪ',
    'could': 'kʊd',
    'my': 'maɪ',
    'than': 'ðæn',
    'first': 'fɜːst',
    'water': 'wɔːtə',
    'been': 'biːn',
    'call': 'kɔːl',
    'who': 'huː',
    'now': 'naʊ',
    'find': 'faɪnd',
    'long': 'lɒŋ',
    'down': 'daʊn',
    'day': 'deɪ',
    'did': 'dɪd',
    'get': 'get',
    'come': 'kʌm',
    'made': 'meɪd',
    'may': 'meɪ',
    'i': 'aɪ',
    'am': 'æm',
    'yes': 'jes',
    'no': 'nəʊ',
    'hello': 'hɛloʊ',
    'hi': 'haɪ',
    'goodbye': 'gʊdbaɪ',
    'thanks': 'θæŋks',
    'thank': 'θæŋk',
    'please': 'pliːz',
    'sorry': 'sɒri',
    'okay': 'əʊkeɪ',
    'ok': 'əʊkeɪ',
  };
}
