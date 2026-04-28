/// A rule-based English G2P converter tuned for KittenTTS.
///
/// KittenTTS internally uses:
///   phonemizer.backend.EspeakBackend(language="en-us", preserve_punctuation=True, with_stress=True)
///
/// This service approximates that pipeline on the Flutter/Dart side so that
/// pre-phonemized IPA can be sent directly to a backend using generate_from_ipa().
///
/// ── TextCleaner vocabulary (from kittentts/onnx_model.py) ────────────────
/// Only characters in this set will be accepted by the server-side tokenizer.
/// Any character outside it is silently dropped (matching the KeyError handler
/// in TextCleaner.__call__). Emitting unknown chars wastes tokens and breaks
/// word shapes, so this service validates its own output via [sanitize].
///
///   Pad:         $
///   Punctuation: ; : , . ! ? ¡ ¿ — … " « » " "   (space)
///   Letters:     A-Z a-z
///   IPA:         ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘ
///                ɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞
///                ↓↑→↗↘ ᵻ (and stress/diacritic combining marks)
///
/// ── AmE vs BrE ───────────────────────────────────────────────────────────
/// The model is trained on en-us eSpeak output. Differences from BrE that
/// matter most:
///   • Short 'o' (hot, lot) → /ɑ/ not /ɒ/
///   • Stressed er/ir/ur    → /ɝ/ (r-coloured) not /ɜː/
///   • Unstressed final er  → /ɚ/ (r-coloured schwa) not /ə/
///   • 'r' is always rhotic → include /ɹ/ after vowels
///
/// ── Limitations ──────────────────────────────────────────────────────────
/// • No stress-mark prediction (ˈ ˌ). The model still works without them.
/// • Numbers, currencies, and abbreviations are NOT expanded. Use the server's
///   clean_text=True flag (TextPreprocessor) or expand them before calling.
/// • This is a heuristic approximation — eSpeak or a neural G2P will always
///   be more accurate for production use.
class PhonemizerService {
  // ─────────────────────────── Vocabulary guard ────────────────────────────

  /// Every IPA character emitted by this service must be in this set.
  /// Matches the _letters_ipa + _punctuation + _letters strings in TextCleaner.
  static final Set<String> _validChars = {
    // Punctuation kept by preserve_punctuation=True
    ';', ':', ',', '.', '!', '?', '¡', '¿', '—', '…',
    '"', '«', '»', '\u201C', '\u201D', ' ',
    // ASCII letters (eSpeak sometimes passes through proper nouns etc.)
    for (int c = 65; c <= 90; c++) String.fromCharCode(c),
    for (int c = 97; c <= 122; c++) String.fromCharCode(c),
    // IPA characters from TextCleaner._letters_ipa
    'ɑ',
    'ɐ',
    'ɒ',
    'æ',
    'ɓ',
    'ʙ',
    'β',
    'ɔ',
    'ɕ',
    'ç',
    'ɗ',
    'ɖ',
    'ð',
    'ʤ',
    'ə',
    'ɘ',
    'ɚ',
    'ɛ',
    'ɜ',
    'ɝ',
    'ɞ',
    'ɟ',
    'ʄ',
    'ɡ',
    'ɠ',
    'ɢ',
    'ʛ',
    'ɦ',
    'ɧ',
    'ħ',
    'ɥ',
    'ʜ',
    'ɨ',
    'ɪ',
    'ʝ',
    'ɭ',
    'ɬ',
    'ɫ',
    'ɮ',
    'ʟ',
    'ɱ',
    'ɯ',
    'ɰ',
    'ŋ',
    'ɳ',
    'ɲ',
    'ɴ',
    'ø',
    'ɵ',
    'ɸ',
    'θ',
    'œ',
    'ɶ',
    'ʘ',
    'ɹ',
    'ɺ',
    'ɾ',
    'ɻ',
    'ʀ',
    'ʁ',
    'ɽ',
    'ʂ',
    'ʃ',
    'ʈ',
    'ʧ',
    'ʉ',
    'ʊ',
    'ʋ',
    'ⱱ', 'ʌ', 'ɣ', 'ɤ', 'ʍ', 'χ', 'ʎ', 'ʏ', 'ʑ', 'ʐ', 'ʒ', 'ʔ', 'ʡ', 'ʕ', 'ʢ',
    'ǀ', 'ǁ', 'ǂ', 'ǃ',
    'ˈ', 'ˌ', 'ː', 'ˑ', 'ʼ', 'ʴ', 'ʰ', 'ʱ', 'ʲ', 'ʷ', 'ˠ', 'ˤ', '˞',
    '↓', '↑', '→', '↗', '↘', 'ᵻ',
    // Combining characters used by eSpeak
    '\u0329', // combining vertical line below (̩)
  };

  // ────────────────────── Silent initial clusters ───────────────────────────

  static const Map<String, String> _silentInitialClusters = {
    'kn': 'n', // knife, know
    'wr': 'ɹ', // write, wrong
    'gn': 'n', // gnome, gnat
    'ps': 's', // psychology
    'pn': 'n', // pneumonia
    'mn': 'm', // mnemonic
  };

  // ──────────────────── Consonant multigraphs ───────────────────────────────
  // Longer entries are always checked before shorter ones at the call site.

  static const Map<String, String> _consonantMultigraphs = {
    'tch': 'tʃ', // catch, watch
    'dge': 'dʒ', // bridge, lodge
    'ch': 'tʃ', // chin, church
    'sh': 'ʃ', // ship, fish
    'zh': 'ʒ', // measure (rare spelling)
    'th': 'θ', // default unvoiced; voiced ð covered in lexicon
    'gh': '', // night, though (silent)
    'ph': 'f', // phone, graph
    'wh': 'w', // where, what
    'ng': 'ŋ', // sing, ring
    'nk': 'ŋk', // think, bank
    'qu': 'kw', // queen, quick
    'ck': 'k', // back, rock
  };

  static const Map<String, String> _singleConsonants = {
    'b': 'b',
    'c': 'k',
    'd': 'd',
    'f': 'f',
    'g': 'ɡ',
    'h': 'h',
    'j': 'dʒ',
    'k': 'k',
    'l': 'l',
    'm': 'm',
    'n': 'n',
    'p': 'p',
    'q': 'k',
    'r': 'ɹ',
    's': 's',
    't': 't',
    'v': 'v',
    'w': 'w',
    'x': 'ks',
    'y': 'j',
    'z': 'z',
  };

  // ─────────────────────── Short vowels (en-us) ─────────────────────────────

  static const Map<String, String> _shortVowels = {
    'a': 'æ', // cat, bad
    'e': 'ɛ', // bed, red
    'i': 'ɪ', // sit, big
    'o': 'ɑ', // hot, lot  ← AmE /ɑ/ not BrE /ɒ/
    'u': 'ʌ', // cup, but
  };

  // ──────────────────── Long vowels (magic-e targets) ───────────────────────

  static const Map<String, String> _longVowels = {
    'a': 'eɪ', // make, cake
    'e': 'iː', // here (rare)
    'i': 'aɪ', // bike, time
    'o': 'oʊ', // hope, home
    'u': 'juː', // cube, mute
  };

  // ──────────────────── Vowel multigraphs ───────────────────────────────────
  // Checked longest-first: trigraphs before digraphs before singles.

  static const Map<String, String> _vowelMultigraphs = {
    // Trigraphs
    'igh': 'aɪ', // night, light
    'ure': 'jʊɹ', // pure, cure   — rhotic AmE
    'ear': 'ɪɹ', // ear, fear    — rhotic AmE
    'air': 'ɛɹ', // air, care    — rhotic AmE
    'oor': 'ʊɹ', // poor, floor  — rhotic AmE
    // r-coloured vowel digraphs (AmE rhotic) — checked before plain digraphs
    'ar': 'ɑːɹ', // car, far
    'er': 'ɝ', // her, fern    — stressed; see _phonemizeCore for unstressed
    'ir': 'ɝ', // bird, girl
    'or': 'ɔːɹ', // for, born
    'ur': 'ɝ', // burn, hurt
    // Pure vowel digraphs
    'ay': 'eɪ', // day, say
    'ai': 'eɪ', // rain, wait
    'ei': 'eɪ', // eight, vein
    'ee': 'iː', // see, feet
    'ea': 'iː', // eat, read   (most common allophone)
    'ie': 'iː', // field, brief
    'oa': 'oʊ', // boat, road
    'ow': 'oʊ', // low, snow   (the /aʊ/ sense is covered in lexicon)
    'oo': 'uː', // food, moon
    'ue': 'uː', // blue, true
    'ew': 'juː', // new, few
    'eu': 'juː', // feud
    'ou': 'aʊ', // out, found
    'oi': 'ɔɪ', // oil, coin
    'oy': 'ɔɪ', // boy, toy
    'au': 'ɔː', // cause, pause
    'aw': 'ɔː', // saw, law
  };

  // ──────────────── Suffixes — longest-first for greedy stripping ───────────

  static const List<MapEntry<String, String>> _suffixes = [
    MapEntry('tion', 'ʃən'), // nation, station
    MapEntry('sion', 'ʒən'), // vision, decision
    MapEntry('ture', 'tʃɚ'), // nature, picture  — AmE rhotic schwa
    MapEntry('ness', 'nɪs'), // kindness
    MapEntry('ment', 'mənt'), // moment
    MapEntry('able', 'əbəl'), // capable
    MapEntry('ible', 'ɪbəl'), // possible
    MapEntry('ical', 'ɪkəl'), // logical
    MapEntry('ious', 'iəs'), // previous
    MapEntry('ance', 'əns'), //rance → balance
    MapEntry('ence', 'əns'), //idence → evidence
    MapEntry('ism', 'ɪzəm'), // criticism
    MapEntry('ity', 'ɪti'), // clarity
    MapEntry('ise', 'aɪz'), // realise
    MapEntry('ize', 'aɪz'), // realize
    MapEntry('ive', 'ɪv'), // active
    MapEntry('ous', 'əs'), // famous
    MapEntry('ful', 'fəl'), // careful
    MapEntry('ing', 'ɪŋ'), // running
    MapEntry('est', 'ɪst'), // fastest
    MapEntry('ist', 'ɪst'), // artist
    MapEntry('ant', 'ənt'), // important
    MapEntry('ent', 'ənt'), // student
    MapEntry('age', 'ɪdʒ'), // village
    MapEntry('less', 'lɪs'), // careless
    MapEntry('ify', 'ɪfaɪ'), // clarify
    MapEntry('fy', 'faɪ'), // simplify
    MapEntry('ly', 'liː'), // quickly
    MapEntry('er', 'ɚ'), // runner — unstressed, AmE rhotic schwa
    MapEntry('ed', 'd'), // walked (simplified; ignores /t/ and /ɪd/)
    MapEntry('s', 'z'), // cats (simplified; ignores /s/)
  ];

  // ─────────────────────────── Public API ──────────────────────────────────

  /// Convert English [text] to IPA compatible with KittenTTS's TextCleaner.
  ///
  /// Punctuation (`.`, `,`, `!`, `?`, `;`, `:`) is preserved in-place,
  /// matching the behaviour of EspeakBackend with preserve_punctuation=True.
  /// The output is space-separated IPA words, ready for the server's
  /// basic_english_tokenize → TextCleaner pipeline (or generate_from_ipa).
  String phonemize(String text) {
    // Preserve sentence-level punctuation but strip everything else.
    final cleaned = text
        .replaceAll(RegExp(r"[^\w\s'.,!?;:]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    final output = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      if (_isPreservablePunctuation(char)) {
        // Keep punctuation with no surrounding space so it attaches to the
        // preceding word token, mirroring eSpeak preserve_punctuation output.
        output.write(char);
      } else if (char == ' ') {
        output.write(' ');
      } else {
        // Collect the whole word then phonemize it.
        final start = i;
        while (i < cleaned.length &&
            cleaned[i] != ' ' &&
            !_isPreservablePunctuation(cleaned[i])) {
          i++;
        }
        i--; // loop will increment
        final word = cleaned.substring(start, i + 1);
        if (word.isNotEmpty) output.write(_phonemizeWord(word));
      }
    }

    return sanitize(output.toString());
  }

  /// Remove any characters that KittenTTS's TextCleaner would silently drop.
  ///
  /// Call this on any IPA string before sending to the backend to ensure
  /// every character maps to a valid token ID.
  String sanitize(String ipa) =>
      ipa.split('').where((c) => _validChars.contains(c)).join();

  // ────────────────────────── Word-level logic ──────────────────────────────

  String _phonemizeWord(String word) {
    if (_commonWords.containsKey(word)) return _commonWords[word]!;

    // Greedy longest-suffix stripping.
    for (final entry in _suffixes) {
      final suffix = entry.key;
      if (word.length > suffix.length + 1 && word.endsWith(suffix)) {
        final stem = word.substring(0, word.length - suffix.length);
        return _phonemizeCore(stem) + entry.value;
      }
    }

    return _phonemizeCore(word);
  }

  // ─────────────────────────── Core engine ─────────────────────────────────

  String _phonemizeCore(String word) {
    if (word.isEmpty) return '';

    final buffer = StringBuffer();
    int i = 0;

    // ── Silent initial cluster (kn-, wr-, gn-, ps-, pn-) ──────────────────
    if (word.length >= 2) {
      final pair = word.substring(0, 2);
      if (_silentInitialClusters.containsKey(pair)) {
        buffer.write(_silentInitialClusters[pair]);
        i = 2;
      }
    }

    while (i < word.length) {
      final char = word[i];
      final isLast = i == word.length - 1;
      final next = isLast ? null : word[i + 1];

      // ── Silent final -e ────────────────────────────────────────────────
      if (char == 'e' && isLast && word.length > 2) {
        i++;
        continue;
      }

      // ── Silent final -mb (lamb, comb, thumb) ──────────────────────────
      if (char == 'm' && next == 'b' && i == word.length - 2) {
        buffer.write('m');
        i += 2;
        continue;
      }

      // ── Vowels ──────────────────────────────────────────────────────────
      if (_isVowel(char)) {
        // Trigraph vowel
        if (i + 2 < word.length) {
          final tri = word.substring(i, i + 3);
          if (_vowelMultigraphs.containsKey(tri)) {
            buffer.write(_vowelMultigraphs[tri]);
            i += 3;
            continue;
          }
        }
        // Digraph vowel — special case: unstressed final 'er' → /ɚ/ (schwa-r)
        if (next != null) {
          final di = word.substring(i, i + 2);
          if (di == 'er' && i == word.length - 2) {
            // Word-final 'er': unstressed rhotic schwa (butter, water)
            buffer.write('ɚ');
            i += 2;
            continue;
          }
          if (_vowelMultigraphs.containsKey(di)) {
            buffer.write(_vowelMultigraphs[di]);
            i += 2;
            continue;
          }
        }
        // Magic-e: V + C(s) + final-e → long vowel
        if (_hasMagicE(word, i)) {
          buffer.write(_longVowels[char] ?? char);
          i++;
          continue;
        }
        // Default short vowel
        buffer.write(_shortVowels[char] ?? char);
        i++;
        continue;
      }

      // ── Consonants ───────────────────────────────────────────────────────

      // Soft-c before e / i / y → /s/
      if (char == 'c' && next != null && 'eiy'.contains(next)) {
        buffer.write('s');
        i++;
        continue;
      }

      // Soft-g before e / i / y → /dʒ/
      if (char == 'g' && next != null && 'eiy'.contains(next)) {
        buffer.write('dʒ');
        i++;
        continue;
      }

      // y as vowel at end of word
      if (char == 'y' && isLast) {
        buffer.write(word.length <= 3 ? 'aɪ' : 'iː');
        i++;
        continue;
      }

      // Silent final -mb
      // (already handled above, but guard for mid-word mb before final e)

      // Consonant trigraph (tch, dge) — checked before digraph
      if (i + 2 < word.length) {
        final tri = word.substring(i, i + 3);
        if (_consonantMultigraphs.containsKey(tri)) {
          buffer.write(_consonantMultigraphs[tri]!);
          i += 3;
          continue;
        }
      }

      // Consonant digraph
      if (next != null) {
        final di = word.substring(i, i + 2);
        if (_consonantMultigraphs.containsKey(di)) {
          buffer.write(_consonantMultigraphs[di]!);
          i += 2;
          continue;
        }
      }

      // Single consonant
      buffer.write(_singleConsonants[char] ?? '');
      i++;
    }

    return buffer.toString();
  }

  // ───────────────────────────── Helpers ───────────────────────────────────

  bool _isVowel(String char) => 'aeiou'.contains(char);

  bool _isPreservablePunctuation(String char) =>
      ','.contains(char) || '.!?;:'.contains(char);

  /// True when the vowel at [index] is lengthened by a trailing silent-e.
  /// Pattern: vowel + one-or-more consonants + final-e (VCe).
  bool _hasMagicE(String word, int index) {
    if (word.isEmpty || word[word.length - 1] != 'e' || word.length < 3) {
      return false;
    }
    int j = index + 1;
    int consonantCount = 0;
    while (j < word.length - 1) {
      if (_isVowel(word[j])) return false;
      consonantCount++;
      j++;
    }
    return consonantCount >= 1;
  }

  // ───────────────────────────── Lexicon ───────────────────────────────────
  // Common words are listed here verbatim as eSpeak en-us would produce them.
  // Voiced-th (ð) words must live here — rule-based cannot predict th voicing.

  static const Map<String, String> _commonWords = {
    // Articles / determiners
    'the': 'ðə', 'a': 'ə', 'an': 'æn',
    // Conjunctions / prepositions
    'and': 'ænd', 'or': 'ɔːɹ', 'but': 'bʌt', 'if': 'ɪf',
    'of': 'ʌv', 'to': 'tuː', 'in': 'ɪn', 'on': 'ɑn',
    'at': 'æt', 'by': 'baɪ', 'as': 'æz',
    'for': 'fɔːɹ', 'with': 'wɪð', 'from': 'fɹʌm', 'into': 'ɪntuː',
    'up': 'ʌp', 'out': 'aʊt', 'over': 'oʊvɚ', 'than': 'ðæn',
    'then': 'ðɛn', 'so': 'soʊ', 'yet': 'jɛt',
    // Pronouns
    'i': 'aɪ', 'you': 'juː', 'he': 'hiː', 'she': 'ʃiː',
    'it': 'ɪt', 'we': 'wiː', 'they': 'ðeɪ',
    'me': 'miː', 'him': 'hɪm', 'her': 'hɜːɹ', 'us': 'ʌs',
    'them': 'ðɛm', 'my': 'maɪ', 'your': 'jɔːɹ', 'his': 'hɪz',
    'its': 'ɪts', 'our': 'aʊɚ', 'their': 'ðɛɹ',
    'this': 'ðɪs', 'that': 'ðæt', 'these': 'ðiːz', 'those': 'ðoʊz',
    'who': 'huː', 'which': 'wɪtʃ', 'what': 'wʌt', 'where': 'wɛɹ',
    'when': 'wɛn', 'how': 'haʊ', 'why': 'waɪ',
    // Auxiliary / modal verbs
    'is': 'ɪz', 'are': 'ɑːɹ', 'was': 'wɑz', 'were': 'wɜːɹ',
    'be': 'biː', 'been': 'biːn', 'being': 'biːɪŋ',
    'have': 'hæv', 'has': 'hæz', 'had': 'hæd',
    'do': 'duː', 'does': 'dʌz', 'did': 'dɪd', 'done': 'dʌn',
    'will': 'wɪl', 'would': 'wʊd', 'can': 'kæn', 'could': 'kʊd',
    'shall': 'ʃæl', 'should': 'ʃʊd', 'may': 'meɪ', 'might': 'maɪt',
    'must': 'mʌst', 'need': 'niːd',
    // Common verbs
    'get': 'ɡɛt', 'got': 'ɡɑt', 'go': 'ɡoʊ', 'went': 'wɛnt',
    'come': 'kʌm', 'came': 'keɪm',
    'make': 'meɪk', 'made': 'meɪd',
    'say': 'seɪ', 'said': 'sɛd',
    'know': 'noʊ', 'think': 'θɪŋk', 'see': 'siː',
    'look': 'lʊk', 'find': 'faɪnd', 'give': 'ɡɪv', 'use': 'juːz',
    'tell': 'tɛl', 'call': 'kɔːl', 'keep': 'kiːp', 'let': 'lɛt',
    'seem': 'siːm', 'feel': 'fiːl', 'try': 'tɹaɪ', 'leave': 'liːv',
    'put': 'pʊt', 'mean': 'miːn', 'show': 'ʃoʊ',
    // Common nouns
    'time': 'taɪm', 'year': 'jɪɹ', 'day': 'deɪ', 'way': 'weɪ',
    'man': 'mæn', 'men': 'mɛn', 'word': 'wɜːɹd',
    'world': 'wɜːɹld', 'life': 'laɪf', 'hand': 'hænd',
    'place': 'pleɪs', 'case': 'keɪs', 'thing': 'θɪŋ', 'home': 'hoʊm',
    'water': 'wɔːtɚ', 'room': 'ɹuːm', 'book': 'bʊk',
    'eye': 'aɪ', 'door': 'dɔːɹ', 'face': 'feɪs', 'name': 'neɪm',
    'people': 'piːpəl', 'child': 'tʃaɪld', 'children': 'tʃɪldɹən',
    // Numbers (eSpeak expands these — caller should use clean_text=True)
    'one': 'wʌn', 'two': 'tuː', 'three': 'θɹiː',
    // Adjectives / adverbs
    'not': 'nɑt', 'all': 'ɔːl', 'some': 'sʌm', 'more': 'mɔːɹ',
    'very': 'vɛɹiː', 'just': 'dʒʌst', 'also': 'ɔːlsoʊ',
    'even': 'iːvən', 'well': 'wɛl', 'such': 'sʌtʃ', 'only': 'oʊnliː',
    'any': 'ɛniː', 'many': 'mɛniː', 'each': 'iːtʃ', 'long': 'lɔːŋ',
    'down': 'daʊn', 'first': 'fɜːɹst', 'other': 'ʌðɚ', 'about': 'əbaʊt',
    // Greetings / discourse
    'hello': 'hɛloʊ', 'hi': 'haɪ', 'hey': 'heɪ',
    'bye': 'baɪ', 'goodbye': 'ɡʊdbaɪ',
    'yes': 'jɛs', 'no': 'noʊ', 'okay': 'oʊkeɪ', 'ok': 'oʊkeɪ',
    'please': 'pliːz', 'thanks': 'θæŋks', 'thank': 'θæŋk',
    'sorry': 'sɑɹiː', 'am': 'æm',
  };
}
