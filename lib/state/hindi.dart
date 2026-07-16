/// Phonetic Latin → Devanagari (Hindi) transliteration.
///
/// Lets users type romanised Hindi ("Hinglish") on a normal keyboard and get
/// proper Devanagari — e.g. `namaste` → नमस्ते, `hindi` → हिन्दी, `aap` → आप.
/// It is intentionally casual and case-insensitive (most people type lowercase),
/// using digraphs for aspirates/long vowels. It won't capture every nuance of
/// Devanagari orthography, but it covers everyday words well.
///
/// Rules:
///  • a consonant carries an inherent "a"; a following vowel replaces it with a
///    matra (the "a" matra is empty), another consonant inserts a virama (्),
///    forming a conjunct.
///  • a vowel at the start of a syllable uses its independent form.
///  • anything unrecognised (space, digits, punctuation) passes through.
library;

const String _virama = '्';

// Consonants → base letter (each implicitly carries the inherent "a").
const Map<String, String> _cons = {
  'chh': 'छ', 'ksh': 'क्ष', 'shh': 'ष', 'gya': 'ज्ञ',
  'kh': 'ख', 'gh': 'घ', 'ng': 'ङ', 'ch': 'च', 'jh': 'झ', 'th': 'थ',
  'dh': 'ध', 'ph': 'फ', 'bh': 'भ', 'sh': 'श', 'gy': 'ज्ञ', 'tr': 'त्र',
  'ny': 'ञ',
  'k': 'क', 'g': 'ग', 'c': 'च', 'j': 'ज', 't': 'त', 'd': 'द', 'n': 'न',
  'p': 'प', 'f': 'फ', 'b': 'ब', 'm': 'म', 'y': 'य', 'r': 'र', 'l': 'ल',
  'v': 'व', 'w': 'व', 's': 'स', 'h': 'ह', 'x': 'क्ष', 'z': 'ज़',
};

// Vowels → (independent form, matra). The "a" matra is empty (inherent).
const Map<String, List<String>> _vow = {
  'aa': ['आ', 'ा'], 'ai': ['ऐ', 'ै'], 'au': ['औ', 'ौ'],
  'ee': ['ई', 'ी'], 'ii': ['ई', 'ी'], 'oo': ['ऊ', 'ू'], 'uu': ['ऊ', 'ू'],
  'a': ['अ', ''], 'i': ['इ', 'ि'], 'u': ['उ', 'ु'],
  'e': ['ए', 'े'], 'o': ['ओ', 'ो'],
};

// All keys, longest first so digraphs (kh, aa, chh…) win over single letters.
final List<String> _keys = () {
  final k = <String>[..._cons.keys, ..._vow.keys];
  k.sort((a, b) => b.length.compareTo(a.length));
  return k;
}();

/// Converts romanised Hindi [input] into Devanagari. Unrecognised characters
/// (spaces, digits, punctuation, emoji) are preserved as-is.
String transliterateHindi(String input) {
  if (input.isEmpty) return input;
  final lower = input.toLowerCase();
  final out = StringBuffer();
  var prevCons = false; // previous unit was a consonant with a pending "a"
  var i = 0;
  while (i < input.length) {
    String? key;
    for (final candidate in _keys) {
      if (lower.startsWith(candidate, i)) {
        key = candidate;
        break;
      }
    }
    if (key == null) {
      out.write(input[i]); // pass through (space / digit / punctuation)
      prevCons = false;
      i += 1;
      continue;
    }
    i += key.length;
    final cons = _cons[key];
    if (cons != null) {
      if (prevCons) out.write(_virama); // join into a conjunct
      out.write(cons);
      prevCons = true;
    } else {
      final v = _vow[key]!;
      out.write(prevCons ? v[1] : v[0]); // matra vs independent
      prevCons = false;
    }
  }
  return out.toString();
}
