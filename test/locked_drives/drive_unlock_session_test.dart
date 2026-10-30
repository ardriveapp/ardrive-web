import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/domain/user_drive_discovery.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

LockedDrive _locked(String id, String owner, int year) => LockedDrive(
      driveId: id,
      ownerAddress: owner,
      signatureType: DriveSignatureType.v2,
      lastUpdated: DateTime(year),
    );

void main() {
  group('DriveUnlockSession', () {
    test('replaces one owner\'s locked drives and keeps them in drive ID order',
        () {
      final session = DriveUnlockSession()
        ..setLockedDrives(
            'me', [_locked('b', 'me', 2025), _locked('a', 'me', 2024)])
        ..setLockedDrives('other', [_locked('c', 'other', 2023)])
        ..setLockedDrives('me', [_locked('d', 'me', 2026)]);

      expect(session.currentLockedDrives.map((d) => d.driveId), ['c', 'd']);
    });

    test(
        'a discovery pass that started before an unlock does not lock the '
        'drive again', () {
      final session = DriveUnlockSession()
        ..setLockedDrives('me', [_locked('a', 'me', 2024)]);
      final passStartedAt = session.unlockGeneration;

      session.markUnlocked('a');
      session.setLockedDrives('me', [_locked('a', 'me', 2024)],
          since: passStartedAt);

      expect(session.isLocked('a'), isFalse);

      // A pass that started after the unlock and still finds it locked is
      // believed.
      session.setLockedDrives('me', [_locked('a', 'me', 2024)],
          since: session.unlockGeneration);
      expect(session.isLocked('a'), isTrue);
    });

    test('markUnlocked takes a drive off the list', () {
      final session = DriveUnlockSession()
        ..setLockedDrives('me', [_locked('a', 'me', 2024)])
        ..markUnlocked('a');

      expect(session.isLocked('a'), isFalse);
    });

    test('a held signature clears a cancelled prompt for that drive', () {
      final session = DriveUnlockSession()..markWalletDeclined('me', 'a');

      session.rememberSignature(
          'me', 'a', DriveSignatureType.v2, Uint8List.fromList([1]));

      expect(session.walletDeclined('me', 'a'), isFalse);
    });

    test('clear forgets everything: nothing outlives a sign-out', () {
      final session = DriveUnlockSession()
        ..setLockedDrives('me', [_locked('a', 'me', 2024)])
        ..rememberSignature(
            'me', 'a', DriveSignatureType.v2, Uint8List.fromList([1]))
        ..markWalletDeclined('me', 'b')
        ..rememberProvenPasswordInfo('a', [1, 2])
        ..setSignInPasswordProven('me', false);

      session.clear();

      expect(session.signInPasswordProven('me'), isNull);
      expect(session.currentLockedDrives, isEmpty);
      expect(session.signature('me', 'a', DriveSignatureType.v2), isNull);
      expect(session.walletDeclined('me', 'b'), isFalse);
      expect(session.provenPasswordInfo('a'), isNull);
    });
  });

  group('PrivateDriveVerdict', () {
    test('a drive a key opened is readable', () {
      expect(
        PrivateDriveVerdict.of(DriveKeyAttempt.opened(
          key: DriveKey(SecretKey([1]), true),
          entity: DriveEntity(id: 'a', rootFolderId: 'r', name: 'A'),
        )),
        PrivateDriveVerdict.readable,
      );
    });

    test('a wrong password or a cancelled prompt is locked', () {
      expect(
          PrivateDriveVerdict.of(
              const DriveKeyAttempt.failed(DriveUnlockFailure.wrongPassword)),
          PrivateDriveVerdict.locked);
      expect(
          PrivateDriveVerdict.of(
              const DriveKeyAttempt.failed(DriveUnlockFailure.walletDeclined)),
          PrivateDriveVerdict.locked);
    });

    test(
        'an unreadable drive is skipped for the pass, never called locked: '
        'a gateway failure says nothing about the password', () {
      expect(
          PrivateDriveVerdict.of(
              const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable)),
          PrivateDriveVerdict.skipped);
    });
  });
}
