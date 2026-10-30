import 'dart:convert';

import 'package:ardrive/locked_drives/domain/drive_fingerprint.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The fingerprint must match desktop's for every drive, so these are pinned
/// to values desktop's own algorithm gives (Node, `crypto.createHash`).
void main() {
  test('6939b9e0-... is 🌌🛡️🌲, as on desktop (hash bytes 184, 235, 80)', () {
    expect(driveFingerprint('6939b9e0-cc98-42cb-bae0-5888eca78885'),
        '\u{1F30C}\u{1F6E1}\u{FE0F}\u{1F332}');
  });

  test('the all-zero drive ID is 🌴🪐🛰️ (hash bytes 18, 185, 55)', () {
    expect(driveFingerprint('00000000-0000-0000-0000-000000000000'),
        '\u{1F334}\u{1FA90}\u{1F6F0}\u{FE0F}');
  });

  test('a capitalised ID gives the same fingerprint as the lowercase one', () {
    expect(driveFingerprint('6939B9E0-CC98-42CB-BAE0-5888ECA78885'),
        driveFingerprint('6939b9e0-cc98-42cb-bae0-5888eca78885'));
  });

  test(
      'the 64 emoji are desktop\'s, byte for byte and in order: SHA-256 of '
      'the list joined by newlines, as computed from drive-fingerprint.ts', () {
    expect(driveFingerprintEmoji, hasLength(64));
    expect(
      _hex(const DartSha256()
          .hashSync(utf8.encode(driveFingerprintEmoji.join('\n')))
          .bytes),
      '8f13c559051b71f2132b69b242360bef3a69e1f48a169ab1b6d384dde87a23b3',
    );
  });

  test('every emoji has a name a screen reader can say', () {
    expect(driveFingerprintEmojiNames, hasLength(64));
    expect(driveFingerprintNames('6939b9e0-cc98-42cb-bae0-5888eca78885'),
        ['milky way', 'shield', 'evergreen tree']);
  });
}
