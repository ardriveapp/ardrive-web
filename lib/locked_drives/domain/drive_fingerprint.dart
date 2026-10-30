import 'dart:convert';

import 'package:cryptography/dart.dart';

/// The 64 emoji a drive fingerprint is drawn from.
///
/// Copied byte for byte, in order, from the desktop app's
/// `src/main/utils/drive-fingerprint.ts`, so one drive shows the same three
/// emoji in both apps. Written as escapes so the variation selectors
/// (U+FE0F) some of them carry are visible in review. Never reorder, add or
/// remove one: every drive's fingerprint would change.
const List<String> driveFingerprintEmoji = [
  '\u{1F4BE}',
  '\u{1F4C0}',
  '\u{1F4BF}',
  '\u{1F5C4}\u{FE0F}',
  '\u{1F4C1}',
  '\u{1F4C2}',
  '\u{1F5C2}\u{FE0F}',
  '\u{1F4BC}',
  '\u{1F48E}',
  '\u{1F4A0}',
  '\u{1F537}',
  '\u{1F536}',
  '\u{2B50}',
  '\u{2728}',
  '\u{1F31F}',
  '\u{1F4AB}',
  '\u{1F332}',
  '\u{1F333}',
  '\u{1F334}',
  '\u{1F335}',
  '\u{1F33F}',
  '\u{1F343}',
  '\u{1F33A}',
  '\u{1F338}',
  '\u{1F525}',
  '\u{1F4A7}',
  '\u{26A1}',
  '\u{1F30A}',
  '\u{1F32A}\u{FE0F}',
  '\u{2600}\u{FE0F}',
  '\u{1F319}',
  '\u{2601}\u{FE0F}',
  '\u{1F985}',
  '\u{1F989}',
  '\u{1F422}',
  '\u{1F418}',
  '\u{1F98F}',
  '\u{1F409}',
  '\u{1F98B}',
  '\u{1F41D}',
  '\u{1F512}',
  '\u{1F510}',
  '\u{1F5DD}\u{FE0F}',
  '\u{1F6E1}\u{FE0F}',
  '\u{2694}\u{FE0F}',
  '\u{1F528}',
  '\u{2692}\u{FE0F}',
  '\u{1F9F2}',
  '\u{1F680}',
  '\u{2708}\u{FE0F}',
  '\u{1F6F8}',
  '\u{1F681}',
  '\u{26F5}',
  '\u{1F388}',
  '\u{1FA82}',
  '\u{1F6F0}\u{FE0F}',
  '\u{1F30C}',
  '\u{1FA90}',
  '\u{2604}\u{FE0F}',
  '\u{1F320}',
  '\u{1F303}',
  '\u{1F305}',
  '\u{1F307}',
  '\u{1F306}',
];

/// A screen reader's name for each of [driveFingerprintEmoji], in the same
/// order: Unicode's short names, so a fingerprint can be read out.
const List<String> driveFingerprintEmojiNames = [
  'floppy disk',
  'DVD',
  'optical disk',
  'file cabinet',
  'file folder',
  'open file folder',
  'card index dividers',
  'briefcase',
  'gem stone',
  'diamond with a dot',
  'large blue diamond',
  'large orange diamond',
  'star',
  'sparkles',
  'glowing star',
  'dizzy',
  'evergreen tree',
  'deciduous tree',
  'palm tree',
  'cactus',
  'herb',
  'leaf fluttering in wind',
  'hibiscus',
  'cherry blossom',
  'fire',
  'droplet',
  'high voltage',
  'water wave',
  'tornado',
  'sun',
  'crescent moon',
  'cloud',
  'eagle',
  'owl',
  'turtle',
  'elephant',
  'rhinoceros',
  'dragon',
  'butterfly',
  'honeybee',
  'locked',
  'locked with key',
  'old key',
  'shield',
  'crossed swords',
  'hammer',
  'hammer and pick',
  'magnet',
  'rocket',
  'airplane',
  'flying saucer',
  'helicopter',
  'sailboat',
  'balloon',
  'parachute',
  'satellite',
  'milky way',
  'ringed planet',
  'comet',
  'shooting star',
  'night with stars',
  'sunrise',
  'sunset',
  'cityscape at dusk',
];

/// The three emoji that identify a drive, from its ID.
///
/// SHA-256 of the lowercase hyphenated drive ID as UTF-8; the first three
/// bytes, each modulo 64, pick from [driveFingerprintEmoji]. The same
/// algorithm as desktop, which hashes the ID as given. Drive IDs are
/// lowercase on chain, so lowercasing here only protects against an ID that
/// reached the app in capitals.
///
/// It identifies the drive, not the password: it is computed from the public
/// ID alone and says nothing about whether a key is right.
List<String> driveFingerprintParts(String driveId) {
  final hash =
      const DartSha256().hashSync(utf8.encode(driveId.toLowerCase())).bytes;

  return [
    for (var i = 0; i < 3; i++)
      driveFingerprintEmoji[hash[i] % driveFingerprintEmoji.length],
  ];
}

/// The names of a drive's three emoji, for a screen reader.
List<String> driveFingerprintNames(String driveId) => [
      for (final emoji in driveFingerprintParts(driveId))
        driveFingerprintEmojiNames[driveFingerprintEmoji.indexOf(emoji)],
    ];

/// [driveFingerprintParts] as one string, as desktop shows it.
String driveFingerprint(String driveId) =>
    driveFingerprintParts(driveId).join();
