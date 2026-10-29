import 'dart:math';

import 'package:flutter/services.dart';

/// How strong a new account's password looks, from its length and the kinds
/// of character in it, after ruling out the common and the repetitive.
///
/// A new account's private files are locked with this password. The wallet
/// signature they are also derived from is the only other secret, and that
/// key is public on Arweave, where a quantum computer could one day break it;
/// the password would then be all that is left, and HKDF does nothing to slow
/// guessing. So new accounts need a strong one. Returning users keep whatever
/// they have.
enum PasswordStrength { tooShort, weak, fair, strong }

/// The fewest characters a new account's password may have.
const newPasswordMinLength = 12;

/// Bits from which a password counts as strong, and as fair.
const _strongBits = 60.0;
const _fairBits = 45.0;

/// A few of the passwords people reach for first. Anything containing one is
/// weak however long it is.
const _common = [
  'password',
  'passw0rd',
  'qwerty',
  'asdfgh',
  'zxcvbn',
  '123456',
  '654321',
  'abc123',
  'letmein',
  'welcome',
  'iloveyou',
  'admin',
  'ardrive',
  'arweave',
  'monkey',
  'dragon',
  'football',
  'baseball',
  'sunshine',
  'princess',
  'master',
  'shadow',
  'superman',
  'trustno1',
  '111111',
  '000000',
];

PasswordStrength assessNewPassword(String password) {
  if (password.runes.length < newPasswordMinLength) {
    return PasswordStrength.tooShort;
  }
  final lower = password.toLowerCase();
  if (_common.any(lower.contains) || _isRepetitive(password)) {
    return PasswordStrength.weak;
  }
  final bits = _estimateBits(password);
  if (bits >= _strongBits) return PasswordStrength.strong;
  if (bits >= _fairBits) return PasswordStrength.fair;
  return PasswordStrength.weak;
}

/// A short word with digits or symbols around it, the most common way people
/// make a password look complex ("Summer2024!!"). The word counts as about
/// one guess in a dictionary of a few thousand, not as random letters.
final _wordWithDecoration =
    RegExp(r'^([^a-zA-Z]{0,4})([a-zA-Z]{1,10})([^a-zA-Z]{0,6})$');

/// Length times the bits of the character kinds used, a deliberately
/// conservative estimate, except for a short word with decoration around it
/// (see [_wordWithDecoration]).
double _estimateBits(String password) {
  final decorated = _wordWithDecoration.firstMatch(password);
  if (decorated != null) {
    final around = decorated.group(1)! + decorated.group(3)!;
    final digits = RegExp(r'[0-9]').allMatches(around).length;
    // ~12 bits for the word, ~4 for its capitalisation, ~3.3 per digit and
    // ~5 per symbol around it.
    return 12 + 4 + digits * 3.32 + (around.length - digits) * 5;
  }
  var pool = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) pool += 26;
  if (RegExp(r'[A-Z]').hasMatch(password)) pool += 26;
  if (RegExp(r'[0-9]').hasMatch(password)) pool += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) pool += 33;
  // Each distinct character counts once more than a repeated one would.
  final distinct = password.runes.toSet().length;
  final length = (password.runes.length + distinct) / 2;
  return length * (log(max(pool, 2)) / ln2);
}

/// Few distinct characters, or one short run repeated ("abcabcabcabc").
bool _isRepetitive(String password) {
  final runes = password.runes.toList();
  if (runes.toSet().length <= 3) return true;
  for (var period = 1; period <= runes.length ~/ 3; period++) {
    var repeats = true;
    for (var i = period; i < runes.length; i++) {
      if (runes[i] != runes[i % period]) {
        repeats = false;
        break;
      }
    }
    if (repeats) return true;
  }
  return false;
}

/// Words from the EFF long list (7,776 words, CC BY 3.0, see
/// `assets/wordlists/LICENSES.md`).
const effWordlistAsset = 'assets/wordlists/eff_large_wordlist.txt';

/// Six words is about 77 bits: out of reach even if the method and the list
/// are known.
const suggestedPassphraseWords = 6;

List<String>? _words;

Future<List<String>> loadPassphraseWords(AssetBundle bundle) async =>
    _words ??= (await bundle.loadString(effWordlistAsset))
        .split('\n')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList(growable: false);

/// A passphrase of [count] words picked uniformly with the platform's secure
/// random source. Made on the device; nothing keeps or sends it.
String suggestPassphrase(
  List<String> words, {
  int count = suggestedPassphraseWords,
  Random? random,
}) {
  final source = random ?? Random.secure();
  // Random.nextInt is uniform for any bound, so no word is favoured.
  return [for (var i = 0; i < count; i++) words[source.nextInt(words.length)]]
      .join('-');
}
