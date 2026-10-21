import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// English titles and buttons are in sentence case: "Create drive", not
/// "CREATE DRIVE" or "Create Drive".
///
/// Only all-caps strings are checked. Title Case cannot be told from a
/// sentence that starts with a name, such as "ArDrive Turbo", without a list
/// of every name, so that part is left to review.
void main() {
  test('no English string is written in capitals', () {
    final strings = (jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>)
      ..removeWhere((key, value) => key.startsWith('@') || value is! String);

    final shouted = <String>[];

    strings.forEach((key, value) {
      // Placeholders and short words, such as "AR", "ID" or "OK", are not
      // shouting.
      final words = (value as String)
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .split(RegExp(r'[^A-Za-z]+'))
          .where((word) => word.length > 3)
          .toList();

      if (words.isNotEmpty && words.every((w) => w == w.toUpperCase())) {
        shouted.add('$key: $value');
      }
    });

    expect(shouted, isEmpty);
  });
}
