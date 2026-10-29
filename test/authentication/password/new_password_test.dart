import 'dart:math';

import 'package:ardrive/authentication/password/new_password.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assessNewPassword', () {
    test('under 12 characters is too short', () {
      expect(assessNewPassword('short'), PasswordStrength.tooShort);
      expect(assessNewPassword('elevenchars'), PasswordStrength.tooShort);
    });

    test('common or repetitive passwords are weak however long', () {
      expect(assessNewPassword('password1234'), PasswordStrength.weak);
      expect(assessNewPassword('MyArDriveFiles2026'), PasswordStrength.weak);
      expect(assessNewPassword('aaaaaaaaaaaaaa'), PasswordStrength.weak);
      expect(assessNewPassword('abcabcabcabc'), PasswordStrength.weak);
    });

    test('a short word dressed up with digits and symbols is weak', () {
      expect(assessNewPassword('Summer2024!!'), PasswordStrength.weak);
      expect(assessNewPassword('!!Football99'), PasswordStrength.weak);
    });

    test('long passphrases and random strings are strong', () {
      expect(assessNewPassword('correcthorsebatterystaple'),
          PasswordStrength.strong);
      expect(assessNewPassword('maple-orbit-quiet-ember-signal-canvas'),
          PasswordStrength.strong);
      expect(assessNewPassword('my cat likes tuna fish'),
          PasswordStrength.strong);
      expect(assessNewPassword('k8#Lq!v2Zp@w'), PasswordStrength.strong);
    });

    test('any character is allowed', () {
      expect(assessNewPassword('über-straße-ñandú-日本語'),
          isNot(PasswordStrength.tooShort));
    });
  });

  group('suggestPassphrase', () {
    final words = [for (var i = 0; i < 7776; i++) 'w$i'];

    test('six words from the list, joined with dashes', () {
      final phrase = suggestPassphrase(words);
      final picked = phrase.split('-');
      expect(picked, hasLength(6));
      expect(picked.every(words.contains), isTrue);
    });

    test('is strong by the same measure new passwords are held to', () {
      final real = ['maple', 'orbit', 'quiet', 'ember', 'signal', 'canvas'];
      expect(assessNewPassword(suggestPassphrase(real, random: Random(1))),
          PasswordStrength.strong);
    });

    test('every word can be picked, none favoured', () {
      final counts = List.filled(8, 0);
      final small = [for (var i = 0; i < 8; i++) '$i'];
      final random = Random(42);
      for (var i = 0; i < 8000; i++) {
        counts[int.parse(suggestPassphrase(small, count: 1, random: random))]++;
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(850, 1150));
      }
    });
  });
}
