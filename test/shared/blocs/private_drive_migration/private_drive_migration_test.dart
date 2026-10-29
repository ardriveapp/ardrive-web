import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/locked_drives/domain/drive_password_info.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/drive_signature_record_builder.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../test_utils/locked_drive_fixtures.dart';
import '../../../test_utils/utils.dart';

const _driveId = '6939b9e0-cc98-42cb-bae0-5888eca78885';
const _otherId = '2c1d4b5e-0f3a-4c8b-9d7e-6a5b4c3d2e1f';

/// Reads a posted record the way every reader does - core-js, the CLI,
/// desktop, web - from the record alone and a fresh wallet signature, and
/// returns the v1 drive key it gives.
Future<List<int>> _readAsAnyApp(
  Wallet wallet,
  DriveSignatureEntity record,
  List<int> passwordInfo,
) async {
  final crypto = ArDriveCrypto();
  final v2 = await crypto.driveKeyFromSignature(
    await crypto.walletSignatureForDrive(
        wallet, record.driveId, DriveSignatureType.v2),
    passwordInfo,
    generated: false,
  );
  final v1Signature = await crypto.decryptStoredDriveSignature(record, v2.key);
  final key = await crypto.driveKeyFromSignature(v1Signature, passwordInfo,
      generated: false);
  return key.key.extractBytes();
}

void main() {
  late Wallet wallet;
  late String owner;
  late MockArweaveService arweave;
  late DriveUnlockSession session;
  late DriveUnlocker unlocker;
  late DriveSignatureRecordBuilder builder;
  late Database db;

  void onChain(PrivateDriveFixture drive) {
    when(() => arweave.getLatestDriveTx(drive.driveId, owner,
            maxRetries: any(named: 'maxRetries')))
        .thenAnswer((_) async => drive.tx);
    when(() => arweave.getEntityDataBytes(drive.tx.id,
            configuredGatewayOnly: any(named: 'configuredGatewayOnly')))
        .thenAnswer((_) async => drive.data);
  }

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '3.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    await AppInfoServices().loadAppInfo();
    wallet = getTestWallet();
    owner = await wallet.getAddress();
    arweave = MockArweaveService();
    session = DriveUnlockSession();
    db = getTestDb();
    unlocker = DriveUnlocker(
      crypto: ArDriveCrypto(),
      arweave: arweave,
      driveDao: db.driveDao,
      session: session,
    );
    builder = DriveSignatureRecordBuilder(
      crypto: ArDriveCrypto(),
      arweave: arweave,
      unlocker: unlocker,
    );
  });

  tearDown(() => db.close());

  group('DriveSignatureRecordBuilder', () {
    test(
        'builds a record under the password that made the drive\'s key, which '
        'any app reads back to that key', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'drive pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);

      final record = await builder.build(
        wallet: wallet,
        driveId: _driveId,
        currentKey: drive.key,
        passwordInfos: [utf8.encode('login pw'), utf8.encode('drive pw')],
      );

      expect(record, isNotNull);
      expect(await _readAsAnyApp(wallet, record!, utf8.encode('drive pw')),
          await drive.key.key.extractBytes());
    });

    test(
        'a password that does not make this drive\'s key - the sign-in '
        'password of a drive made with another - builds nothing', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'drive pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);

      expect(
        await builder.build(
          wallet: wallet,
          driveId: _driveId,
          currentKey: drive.key,
          passwordInfos: [utf8.encode('login pw')],
        ),
        isNull,
      );
    });

    test('a key that does not open the drive builds nothing', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'drive pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);

      expect(
        await builder.build(
          wallet: wallet,
          driveId: _driveId,
          currentKey: DriveKey(SecretKey(List.filled(32, 3)), true),
          passwordInfos: [utf8.encode('drive pw')],
        ),
        isNull,
      );
    });

    test('a drive that is not v1 builds nothing', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet, driveId: _driveId, password: 'drive pw');
      onChain(drive);

      expect(
        await builder.build(
          wallet: wallet,
          driveId: _driveId,
          currentKey: drive.key,
          passwordInfos: [utf8.encode('drive pw')],
        ),
        isNull,
      );
    });

    test('a drive that can\'t be read builds nothing', () async {
      when(() => arweave.getLatestDriveTx(_driveId, owner,
              maxRetries: any(named: 'maxRetries')))
          .thenThrow(Exception('offline'));

      expect(
        await builder.build(
          wallet: wallet,
          driveId: _driveId,
          currentKey: DriveKey(SecretKey(List.filled(32, 3)), true),
          passwordInfos: [utf8.encode('drive pw')],
        ),
        isNull,
      );
    });

    test(
        'a core-js drive with a non-ASCII password gets its record under the '
        'double-encoded password, which is what core-js reads it with',
        () async {
      final drive = await makePrivateDrive(
        wallet: wallet,
        driveId: _driveId,
        passwordInfo: coreJsPasswordInfo('pässwörd'),
        signatureType: DriveSignatureType.v1,
      );
      onChain(drive);

      final record = await builder.build(
        wallet: wallet,
        driveId: _driveId,
        currentKey: drive.key,
        passwordInfos: drivePasswordInfos('pässwörd'),
      );

      expect(
          await _readAsAnyApp(wallet, record!, coreJsPasswordInfo('pässwörd')),
          await drive.key.key.extractBytes());
    });
  });

  group('PrivateDriveMigrationBloc', () {
    late MockDrivesCubit drivesCubit;
    late MockArDriveAuth auth;
    late List<DataItem> posted;
    final profileKey = SecretKey(List.filled(32, 5));

    Future<Drive> v1DriveRow(PrivateDriveFixture drive) async {
      final entity =
          (await unlocker.openWithKey(drive.tx, drive.data, drive.key))!;
      await db.driveDao.writeDriveEntity(
        name: entity.name!,
        entity: entity,
        driveKey: drive.key,
        profileKey: profileKey,
      );
      return db.driveDao.driveById(driveId: drive.driveId).getSingle();
    }

    PrivateDriveMigrationBloc buildBloc(List<Drive> rows) {
      when(() => drivesCubit.state).thenReturn(DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: rows,
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ));
      return PrivateDriveMigrationBloc(
        drivesCubit: drivesCubit,
        driveDao: db.driveDao,
        ardriveAuth: auth,
        crypto: ArDriveCrypto(),
        turboUploadService: MockTurboUploadService(),
        arweave: arweave,
        driveUnlocker: unlocker,
        postRecord: (dataItem, _) async => posted.add(dataItem),
      );
    }

    DriveSignatureEntity recordOf(DataItem item) =>
        DriveSignatureEntity.fromTransaction(
          FakeDriveTx(
            id: 'posted',
            ownerAddress: owner,
            tags: {
              for (final tag in item.tags)
                utils.decodeBase64ToString(tag.name):
                    utils.decodeBase64ToString(tag.value)
            },
          ),
          item.data,
        );

    setUp(() {
      posted = [];
      drivesCubit = MockDrivesCubit();
      whenListen(drivesCubit, const Stream<DrivesState>.empty());
      auth = MockArDriveAuth();
      when(() => auth.isUserLoggedIn()).thenAnswer((_) async => true);
      when(() => auth.currentUser).thenReturn(User(
        password: 'login pw',
        wallet: wallet,
        walletAddress: owner,
        walletBalance: BigInt.zero,
        cipherKey: profileKey,
        profileType: ProfileType.json,
        errorFetchingIOTokens: false,
      ));
    });

    test('migrates a drive the sign-in password made, with that password',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'login pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);
      final bloc = buildBloc([await v1DriveRow(drive)]);

      bloc.add(const PrivateDriveMigrationStartEvent());
      await expectLater(
          bloc.stream, emitsThrough(isA<PrivateDriveMigrationComplete>()));

      expect(posted, hasLength(1));
      expect(
          await _readAsAnyApp(
              wallet, recordOf(posted.single), utf8.encode('login pw')),
          await drive.key.key.extractBytes());
      await bloc.close();
    });

    test(
        'a drive unlocked this session with its own password is migrated with '
        'that password, never the sign-in one', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'own pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);
      session.rememberProvenPasswordInfo(_driveId, utf8.encode('own pw'));
      final bloc = buildBloc([await v1DriveRow(drive)]);

      bloc.add(const PrivateDriveMigrationStartEvent());
      await expectLater(
          bloc.stream, emitsThrough(isA<PrivateDriveMigrationComplete>()));

      expect(
          await _readAsAnyApp(
              wallet, recordOf(posted.single), utf8.encode('own pw')),
          await drive.key.key.extractBytes());
      await bloc.close();
    });

    test(
        'a drive whose password is not known this session posts nothing: the '
        'sign-in password would have written a record that breaks it',
        () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'own pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);
      final bloc = buildBloc([await v1DriveRow(drive)]);

      bloc.add(const PrivateDriveMigrationStartEvent());
      await expectLater(
          bloc.stream, emitsThrough(isA<PrivateDriveMigrationFailed>()));

      expect(posted, isEmpty);
      await bloc.close();
    });

    test('never migrates a locked drive', () async {
      final drive = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'login pw',
          signatureType: DriveSignatureType.v1);
      onChain(drive);
      final row = await v1DriveRow(drive);
      session.setLockedDrives(owner, [
        LockedDrive(
          driveId: _driveId,
          ownerAddress: owner,
          signatureType: DriveSignatureType.v1,
          lastUpdated: DateTime(2026),
        ),
      ]);
      final bloc = buildBloc([row]);

      bloc.add(const PrivateDriveMigrationStartEvent());
      await expectLater(
          bloc.stream, emitsThrough(isA<PrivateDriveMigrationFailed>()));

      expect(posted, isEmpty);
      await bloc.close();
    });

    test('a failed drive does not stop the others', () async {
      final unknown = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _otherId,
          password: 'own pw',
          signatureType: DriveSignatureType.v1);
      final known = await makeWebPrivateDrive(
          wallet: wallet,
          driveId: _driveId,
          password: 'login pw',
          signatureType: DriveSignatureType.v1);
      onChain(unknown);
      onChain(known);
      final bloc =
          buildBloc([await v1DriveRow(unknown), await v1DriveRow(known)]);

      bloc.add(const PrivateDriveMigrationStartEvent());
      await expectLater(
          bloc.stream, emitsThrough(isA<PrivateDriveMigrationFailed>()));

      expect(posted.map((item) => recordOf(item).driveId), [_driveId]);
      await bloc.close();
    });
  });
}
