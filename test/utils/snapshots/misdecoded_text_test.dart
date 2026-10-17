import 'dart:convert';

import 'package:ardrive/utils/snapshots/misdecoded_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// [name] as reading its UTF-8 a byte at a time left it.
String damaged(String name) => String.fromCharCodes(utf8.encode(name));

void main() {
  group('repairMisdecodedUtf8', () {
    for (final name in [
      'Talks — 2024',
      'Café',
      'Ünïcödé',
      '日本の写真',
      'Trip 🏔️',
      '“Quoted” – en dash … ellipsis',
    ]) {
      test('undoes the damage to "$name"', () {
        expect(damaged(name), isNot(name), reason: 'it was damaged');
        expect(repairMisdecodedUtf8(damaged(name)), name);
      });
    }

    test('leaves a name that was never damaged as it is', () {
      for (final name in [
        'Plain ASCII',
        'Café', // a lone é is not UTF-8, so it cannot be damage
        'Talks — 2024',
        '日本',
        '',
      ]) {
        expect(repairMisdecodedUtf8(name), name, reason: name);
      }
    });

    test('is safe to run twice', () {
      final once = repairMisdecodedUtf8(damaged('Talks — 2024'));

      expect(repairMisdecodedUtf8(once), 'Talks — 2024');
    });
  });
}
