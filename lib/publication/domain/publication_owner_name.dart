/// Whether [name], as a publication's display name (the "By ..." owner name),
/// would pass for ArDrive, ar.io or Turbo: "ArDrive Support", "Official
/// ArDrive", "AR.IO", "Turbo Team" and the like (docs/ArweaveFS.md,
/// "Publication").
///
/// Only the display name is held to this. A page's title, a drive's name and
/// any other text may say ArDrive: "ArDrive Photos Drive" is a fine title.
///
/// Case, spaces, punctuation and the usual look-alike characters are
/// normalised first. "ardrive" is refused anywhere in the name, joined up;
/// "turbo" and "ario" (or "ar" then "io") only as words, so "Mario" and
/// "Turbochargers" stay usable.
bool isReservedPublicationOwnerName(String name) {
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_lookAlikes[char] ?? char);
  }
  final words = buffer
      .toString()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.join().contains('ardrive')) return true;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (word == 'turbo' || word == 'ario') return true;
    if (word == 'ar' && i + 1 < words.length && words[i + 1] == 'io') {
      return true;
    }
  }
  return false;
}

/// Characters that read as a Latin letter: digits and symbols people swap
/// in, and the Cyrillic and Greek letters drawn like Latin ones.
const _lookAlikes = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a',
  '!': 'i',
  '\$': 's',
  // Cyrillic
  'а': 'a',
  'в': 'b',
  'е': 'e',
  'і': 'i',
  'ї': 'i',
  'о': 'o',
  'р': 'p',
  'с': 'c',
  'т': 't',
  'у': 'y',
  'х': 'x',
  'ԁ': 'd',
  'ѵ': 'v',
  // Greek
  'α': 'a',
  'ε': 'e',
  'ι': 'i',
  'ο': 'o',
  'ρ': 'p',
  'τ': 't',
  'υ': 'u',
  'ν': 'v',
};
