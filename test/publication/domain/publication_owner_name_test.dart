import 'package:ardrive/publication/domain/publication_owner_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names that pass for ArDrive, ar.io or Turbo are reserved', () {
    for (final name in [
      'ArDrive',
      'ardrive',
      'ArDrive Support',
      'ArDrive Team',
      'Official ArDrive',
      'Ar Drive',
      'AR-DRIVE',
      'ar.drive',
      'ArDr1ve',
      'ArDr!ve',
      'TheArDriveTeam',
      // A Cyrillic "а" and "е" drawn like Latin letters.
      'Аrdrivе',
      'ar.io',
      'AR.IO',
      'ar io',
      'ARIO',
      'ARIO Network',
      'Turbo',
      'Turbo Team',
      'turbo support',
    ]) {
      expect(isReservedPublicationOwnerName(name), isTrue, reason: name);
    }
  });

  test('everyday names are not', () {
    for (final name in [
      'Phil',
      'Mario',
      'Dario Rossi',
      'Rosario',
      'Scenario Labs',
      'Turbochargers Club',
      'Hard Drive Archive',
      'Arweave fan',
      '',
    ]) {
      expect(isReservedPublicationOwnerName(name), isFalse, reason: name);
    }
  });
}
