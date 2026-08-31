import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Every English string has to be drawable in the face it is drawn in.
///
/// Wavehaus is the brand face and the app's default, and none of its six
/// weights contains an em dash (U+2014), an en dash (U+2013) or a horizontal
/// ellipsis (U+2026) - checked below against the fonts' own cmaps rather than
/// asserted from memory. A string containing one is not drawn wrong in an
/// obvious way; it is drawn in whatever fallback the platform happens to pick,
/// so one character of a sentence arrives in a different typeface at a
/// different weight. "Up to date - nothing new" was the most-seen string this
/// work added.
///
/// Read off the ARB rather than off the rendered app, because that is where a
/// new string is written and this is meant to fail the moment one is.
void main() {
  /// The characters a face can draw, from its `cmap` table.
  ///
  /// Formats 4 and 12 only: those are the two these files use. Anything else
  /// is ignored, which can only make this check *less* strict - it can report
  /// a character as missing that is present, never the other way round, so it
  /// cannot pass a string it should fail.
  Set<int> coveredCharacters(File file) {
    final bytes = ByteData.view(
      Uint8List.fromList(file.readAsBytesSync()).buffer,
    );

    final tableCount = bytes.getUint16(4);
    var cmapOffset = -1;
    for (var i = 0; i < tableCount; i++) {
      final record = 12 + 16 * i;
      final tag = String.fromCharCodes([
        for (var b = 0; b < 4; b++) bytes.getUint8(record + b),
      ]);
      if (tag == 'cmap') {
        cmapOffset = bytes.getUint32(record + 8);
      }
    }
    expect(cmapOffset, isNot(-1), reason: '${file.path} has no cmap table');

    final covered = <int>{};
    final subtableCount = bytes.getUint16(cmapOffset + 2);

    for (var i = 0; i < subtableCount; i++) {
      final record = cmapOffset + 4 + 8 * i;
      final subtable = cmapOffset + bytes.getUint32(record + 4);
      final format = bytes.getUint16(subtable);

      if (format == 4) {
        final segCountX2 = bytes.getUint16(subtable + 6);
        final segCount = segCountX2 ~/ 2;
        for (var s = 0; s < segCount; s++) {
          final end = bytes.getUint16(subtable + 14 + s * 2);
          final start = bytes.getUint16(subtable + 16 + segCountX2 + s * 2);
          if (start == 0xFFFF && end == 0xFFFF) continue;
          for (var c = start; c <= end; c++) {
            covered.add(c);
          }
        }
      } else if (format == 12) {
        final groups = bytes.getUint32(subtable + 12);
        for (var g = 0; g < groups; g++) {
          final group = subtable + 16 + 12 * g;
          final start = bytes.getUint32(group);
          final end = bytes.getUint32(group + 4);
          for (var c = start; c <= end && c - start < 0x10000; c++) {
            covered.add(c);
          }
        }
      }
    }

    return covered;
  }

  late Set<int> drawableInEveryWeight;

  setUpAll(() {
    final faces = Directory('packages/ardrive_ui/assets/fonts')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('Wavehaus'))
        .toList();

    expect(faces, hasLength(6), reason: 'the six Wavehaus weights');

    drawableInEveryWeight =
        faces.map(coveredCharacters).reduce((a, b) => a.intersection(b));
  });

  test('the three marks this rule is about really are missing', () {
    // The premise, checked rather than assumed: if a later version of the
    // font adds them, this test says so instead of quietly enforcing a rule
    // that no longer has a reason.
    for (final absent in {
      'em dash': 0x2014,
      'en dash': 0x2013,
      'horizontal ellipsis': 0x2026,
    }.entries) {
      expect(drawableInEveryWeight, isNot(contains(absent.value)),
          reason: 'Wavehaus now has an ${absent.key}; this rule can be '
              'relaxed');
    }

    // And the substitutes actually used, so a fix cannot swap one missing
    // character for another.
    for (final present in {
      'hyphen': 0x2D,
      'comma': 0x2C,
      'full stop': 0x2E,
      'colon': 0x3A,
      'right single quote': 0x2019,
    }.entries) {
      expect(drawableInEveryWeight, contains(present.value),
          reason: 'the substitute for a missing mark has to be a character '
              'the face has: ${present.key}');
    }
  });

  test('no English string uses a character the brand face cannot draw', () {
    final arb = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

    final offenders = <String, String>{};

    arb.forEach((key, value) {
      // `@key` entries are translator metadata, and `@@locale` is a header.
      if (key.startsWith('@') || value is! String) return;

      for (final rune in value.runes) {
        // ASCII is universally covered and is most of every string; only the
        // rest is worth asking the font about.
        if (rune < 0x80) continue;
        if (drawableInEveryWeight.contains(rune)) continue;

        offenders[key] = value;
        break;
      }
    });

    expect(
      offenders,
      isEmpty,
      reason: 'these strings contain a character no Wavehaus weight can draw, '
          'so part of the sentence is rendered in a fallback face',
    );
  });
}
