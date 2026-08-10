import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// A transaction that answers `getTag`, which is all the cubit asks of one.
class _TransactionWithTags extends Fake implements TransactionCommonMixin {
  _TransactionWithTags(this._tags);

  final Map<String, String> _tags;

  @override
  List<TransactionCommonMixin$Tag> get tags => _tags.entries
      .map((e) => TransactionCommonMixin$Tag()
        ..name = e.key
        ..value = e.value)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `deriveFileKey` parses the file id as a uuid, so these have to be real
  // uuids rather than the usual test placeholders.
  const driveId = '00000000-0000-0000-0000-000000000001';
  const fileId = '8f3c2a10-6f4e-4c7a-9b2e-1d2f3a4b5c6d';
  const rootFolderId = '00000000-0000-0000-0000-000000000003';

  // The ids of the design plan's example links, §1.3.
  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';
  const bundledInTxId = 'oLd7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWe';
  const thumbnailTxId = 'oLdzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBn0';

  // 12 IV bytes are 16 base64url characters.
  const cipherIv = '9tR2kX0pLmQz8sQ1';

  const fileName = 'Q3 Report.pdf';
  const fileSize = 4821133;
  const contentType = 'application/pdf';

  final date = DateTime(2024, 3, 14, 9, 30);
  final profileKey = SecretKey(List.filled(32, 3));
  final driveKey = SecretKey(List.filled(32, 7));

  late Database db;
  late DriveDao driveDao;
  late ArweaveService arweave;
  late ProfileCubit profileCubit;

  /// The route location of a share link - the part after the `#`, which is
  /// where the query of a hash route lives.
  Uri locationOf(Uri link) => Uri.parse(link.toString().replaceFirst('/#', ''));

  Map<String, String> parametersOf(FileShareLoadSuccess state) =>
      locationOf(state.fileShareLink).queryParameters;

  Future<void> insertDrive({required String privacy}) async {
    var drive = DrivesCompanion.insert(
      id: driveId,
      rootFolderId: rootFolderId,
      ownerAddress: ownerAddress,
      name: 'drive',
      privacy: privacy,
    );

    if (privacy == DrivePrivacyTag.private) {
      // Exactly what `DriveDao._addDriveKeyToDriveCompanion` writes, so that
      // `getDriveKey` reads the drive key back out.
      final encryption = await AesGcm.with256bits().encrypt(
        await driveKey.extractBytes(),
        secretKey: profileKey,
      );

      drive = drive.copyWith(
        encryptedKey: Value(encryption.concatenation(nonce: false)),
        keyEncryptionIv: Value(Uint8List.fromList(encryption.nonce)),
      );
    }

    await db.into(db.drives).insert(drive);
  }

  Future<void> insertFile({
    String dataTxStatus = TransactionStatus.confirmed,
    bool withThumbnail = true,
    bool withRevision = true,
  }) async {
    final thumbnail = withThumbnail
        ? jsonEncode({
            'variants': [
              {
                'name': 'small',
                'txId': thumbnailTxId,
                'size': 1024,
                'width': 100,
                'height': 100,
              }
            ]
          })
        : null;

    await db.batch((batch) {
      batch.insert(
        db.fileEntries,
        FileEntriesCompanion.insert(
          id: fileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: fileName,
          dataTxId: dataTxId,
          size: fileSize,
          dateCreated: Value(date),
          lastModifiedDate: date,
          dataContentType: const Value(contentType),
          bundledIn: const Value(bundledInTxId),
          thumbnail: Value(thumbnail),
          isHidden: const Value(false),
          path: '',
        ),
      );

      if (withRevision) {
        batch.insert(
          db.fileRevisions,
          FileRevisionsCompanion.insert(
            fileId: fileId,
            driveId: driveId,
            parentFolderId: rootFolderId,
            name: fileName,
            metadataTxId: metadataTxId,
            dataTxId: dataTxId,
            size: fileSize,
            dateCreated: Value(date),
            lastModifiedDate: date,
            dataContentType: const Value(contentType),
            bundledIn: const Value(bundledInTxId),
            thumbnail: Value(thumbnail),
            action: RevisionAction.create,
            isHidden: const Value(false),
          ),
        );
      }

      batch.insertAll(db.networkTransactions, [
        NetworkTransactionsCompanion.insert(
          id: dataTxId,
          status: Value(dataTxStatus),
          dateCreated: Value(date),
        ),
        NetworkTransactionsCompanion.insert(
          id: metadataTxId,
          status: const Value(TransactionStatus.confirmed),
          dateCreated: Value(date),
        ),
      ]);
    });
  }

  /// Replaces the file rows of the group's setUp with a different shape.
  Future<void> resetFile({
    bool withThumbnail = true,
    bool withRevision = true,
  }) async {
    await db.delete(db.fileRevisions).go();
    await db.delete(db.fileEntries).go();
    await db.delete(db.networkTransactions).go();

    await insertFile(
      withThumbnail: withThumbnail,
      withRevision: withRevision,
    );
  }

  FileShareCubit createCubit() => FileShareCubit(
        driveId: driveId,
        fileId: fileId,
        profileCubit: profileCubit,
        driveDao: driveDao,
        arweave: arweave,
      );

  /// Waits for the share details, including the background cipher lookup.
  Future<FileShareLoadSuccess> loaded(FileShareCubit cubit) async =>
      await cubit.stream.firstWhere(
        (state) =>
            state is FileShareLoadSuccess && !state.isLoadingCipherDetails,
      ) as FileShareLoadSuccess;

  setUp(() async {
    db = getTestDb();
    driveDao = db.driveDao;
    arweave = MockArweaveService();
    profileCubit = MockProfileCubit();

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(
        user: User(
          password: 'password',
          wallet: getTestWallet(),
          walletAddress: ownerAddress,
          walletBalance: BigInt.one,
          cipherKey: profileKey,
          profileType: ProfileType.json,
          ioTokens: 'ioTokens',
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ),
    );

    when(() => arweave.getTransactionDetails(any())).thenAnswer(
      (_) async => _TransactionWithTags({
        EntityTag.cipher: Cipher.aes256gcm,
        EntityTag.cipherIv: cipherIv,
      }),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('public files', () {
    setUp(() async {
      await insertDrive(privacy: DrivePrivacyTag.public);
      await insertFile();
    });

    blocTest<FileShareCubit, FileShareState>(
      'builds a v2 link out of the local database alone',
      build: createCubit,
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        final state = cubit.state as FileShareLoadSuccess;

        expect(parametersOf(state), {
          SharedFileLinkParams.version: '2',
          SharedFileLinkParams.dataTxId: dataTxId,
          SharedFileLinkParams.metadataTxId: metadataTxId,
          SharedFileLinkParams.owner: ownerAddress,
          SharedFileLinkParams.name: fileName,
          SharedFileLinkParams.size: '$fileSize',
          SharedFileLinkParams.contentType: contentType,
          SharedFileLinkParams.bundledIn: bundledInTxId,
          SharedFileLinkParams.thumbnailTxId: thumbnailTxId,
        });

        expect(state.isPublicFile, isTrue);
        expect(state.fileName, fileName);
        expect(state.fileKeyBase64, isNull);
        expect(state.hasSeparateKeyArtifact, isFalse);
        expect(state.isLoadingCipherDetails, isFalse);

        // A public file has nothing to decrypt, so nothing to look up.
        verifyNever(() => arweave.getTransactionDetails(any()));
      },
    );

    test('a file with no thumbnail simply omits thn', () async {
      await resetFile(withThumbnail: false);

      final state = await loaded(createCubit());

      expect(
        parametersOf(state).containsKey(SharedFileLinkParams.thumbnailTxId),
        isFalse,
      );
      expect(parametersOf(state)[SharedFileLinkParams.dataTxId], dataTxId);
    });

    test('a file with no revision row still gets a link, without mtx',
        () async {
      await resetFile(withRevision: false);

      final state = await loaded(createCubit());

      expect(
        parametersOf(state).containsKey(SharedFileLinkParams.metadataTxId),
        isFalse,
      );
      expect(parametersOf(state)[SharedFileLinkParams.dataTxId], dataTxId);
      expect(
        parametersOf(state)[SharedFileLinkParams.thumbnailTxId],
        thumbnailTxId,
      );
    });
  });

  group('private files', () {
    setUp(() async {
      await insertDrive(privacy: DrivePrivacyTag.private);
      await insertFile();
    });

    Future<String> expectedFileKey() async => encodeBytesToBase64(
          await (await driveDao.getFileKey(fileId, driveKey)).extractBytes(),
        );

    blocTest<FileShareCubit, FileShareState>(
      'shows the link before the cipher details land, then folds them in',
      build: createCubit,
      wait: const Duration(milliseconds: 100),
      expect: () => containsAllInOrder([
        // The link is complete except for `c`/`iv` and already copyable.
        isA<FileShareLoadSuccess>()
            .having(
              (s) => s.isLoadingCipherDetails,
              'isLoadingCipherDetails',
              isTrue,
            )
            .having(
              (s) => parametersOf(s),
              'parameters',
              allOf(
                containsPair(SharedFileLinkParams.dataTxId, dataTxId),
                isNot(contains(SharedFileLinkParams.cipher)),
                isNot(contains(SharedFileLinkParams.cipherIv)),
              ),
            ),
        isA<FileShareLoadSuccess>()
            .having(
              (s) => s.isLoadingCipherDetails,
              'isLoadingCipherDetails',
              isFalse,
            )
            .having(
              (s) => parametersOf(s),
              'parameters',
              allOf(
                containsPair(SharedFileLinkParams.cipher, Cipher.aes256gcm),
                containsPair(SharedFileLinkParams.cipherIv, cipherIv),
              ),
            ),
      ]),
    );

    test('the default link is keyless and the key is a separate artifact',
        () async {
      final state = await loaded(createCubit());

      expect(parametersOf(state), {
        SharedFileLinkParams.version: '2',
        SharedFileLinkParams.dataTxId: dataTxId,
        SharedFileLinkParams.metadataTxId: metadataTxId,
        SharedFileLinkParams.owner: ownerAddress,
        SharedFileLinkParams.name: fileName,
        SharedFileLinkParams.size: '$fileSize',
        SharedFileLinkParams.contentType: contentType,
        SharedFileLinkParams.cipher: Cipher.aes256gcm,
        SharedFileLinkParams.cipherIv: cipherIv,
        SharedFileLinkParams.bundledIn: bundledInTxId,
        SharedFileLinkParams.thumbnailTxId: thumbnailTxId,
      });

      expect(state.isPublicFile, isFalse);
      expect(state.keyIsInLink, isFalse);
      expect(state.fileKeyBase64, await expectedFileKey());
      expect(state.hasSeparateKeyArtifact, isTrue);
      expect(
        state.fileShareLink.toString(),
        isNot(contains(state.fileKeyBase64!)),
      );
    });

    test('opting in puts the key in the link and nowhere else', () async {
      final cubit = createCubit();
      await loaded(cubit);

      cubit.setKeyIsInLink(true);

      final state = cubit.state as FileShareLoadSuccess;
      final fileKey = await expectedFileKey();

      expect(state.keyIsInLink, isTrue);
      expect(parametersOf(state)[SharedFileLinkParams.key], fileKey);
      expect(locationOf(state.fileShareLink).fragment, isEmpty);
      expect(
        parametersOf(state).containsKey(SharedFileLinkParams.legacyKey),
        isFalse,
      );
      // The key is still offered on its own until the sharer opts in - and
      // once they do, there is only one artifact left to hand over.
      expect(state.hasSeparateKeyArtifact, isFalse);

      cubit.setKeyIsInLink(false);

      final keyless = cubit.state as FileShareLoadSuccess;

      expect(keyless.fileShareLink.toString(), isNot(contains(fileKey)));
      expect(keyless.hasSeparateKeyArtifact, isTrue);
    });

    test('hiding the details omits n, s and ct and sets hid', () async {
      final cubit = createCubit();
      await loaded(cubit);

      cubit.setDetailsAreHidden(true);

      final state = cubit.state as FileShareLoadSuccess;
      final parameters = parametersOf(state);

      expect(state.detailsAreHidden, isTrue);
      expect(parameters[SharedFileLinkParams.hidden], '1');
      expect(parameters.containsKey(SharedFileLinkParams.name), isFalse);
      expect(parameters.containsKey(SharedFileLinkParams.size), isFalse);
      expect(parameters.containsKey(SharedFileLinkParams.contentType), isFalse);
      expect(state.fileShareLink.toString(), isNot(contains('Report')));

      // The rest of the link is untouched: hiding is not a downgrade.
      expect(parameters[SharedFileLinkParams.dataTxId], dataTxId);
      expect(parameters[SharedFileLinkParams.cipher], Cipher.aes256gcm);
      expect(parameters[SharedFileLinkParams.cipherIv], cipherIv);

      cubit.setDetailsAreHidden(false);

      final shown = cubit.state as FileShareLoadSuccess;

      expect(
        parametersOf(shown).containsKey(SharedFileLinkParams.hidden),
        isFalse,
      );
      expect(parametersOf(shown)[SharedFileLinkParams.name], fileName);
    });

    test('pinning sets pin and leaves live links without it', () async {
      final cubit = createCubit();
      final live = await loaded(cubit);

      expect(
        parametersOf(live).containsKey(SharedFileLinkParams.pinned),
        isFalse,
      );

      cubit.setPinnedToCurrentVersion(true);

      final pinned = cubit.state as FileShareLoadSuccess;

      expect(pinned.isPinned, isTrue);
      expect(parametersOf(pinned)[SharedFileLinkParams.pinned], '1');
      expect(parametersOf(pinned)[SharedFileLinkParams.dataTxId], dataTxId);
      expect(
        parametersOf(pinned)[SharedFileLinkParams.metadataTxId],
        metadataTxId,
      );
    });

    test('a failed cipher lookup still yields a usable link', () async {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => throw Exception('gateway is unreachable'));

      final state = await loaded(createCubit());
      final parameters = parametersOf(state);

      expect(parameters.containsKey(SharedFileLinkParams.cipher), isFalse);
      expect(parameters.containsKey(SharedFileLinkParams.cipherIv), isFalse);
      expect(state.isLoadingCipherDetails, isFalse);
      expect(state.fileKeyBase64, await expectedFileKey());

      // Everything else is still there, so the recipient pays one GraphQL
      // request at download time and nothing more (§1.2).
      final payload =
          SharedFileLinkPayload.tryParse(locationOf(state.fileShareLink));

      expect(payload, isNotNull);
      expect(payload!.hasFastPathTarget, isTrue);
      expect(payload.hasCipherDetails, isFalse);
      expect(payload.name, fileName);
    });

    test('a transaction without cipher tags yields a usable link', () async {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _TransactionWithTags(const {}));

      final state = await loaded(createCubit());

      expect(
        parametersOf(state).containsKey(SharedFileLinkParams.cipher),
        isFalse,
      );
      expect(parametersOf(state)[SharedFileLinkParams.dataTxId], dataTxId);
    });
  });

  group('unshareable files', () {
    blocTest<FileShareCubit, FileShareState>(
      'emits FileShareLoadedFailedFile when the data transaction failed',
      setUp: () async {
        await insertDrive(privacy: DrivePrivacyTag.public);
        await insertFile(dataTxStatus: TransactionStatus.failed);
      },
      build: createCubit,
      wait: const Duration(milliseconds: 100),
      expect: () => contains(isA<FileShareLoadedFailedFile>()),
      verify: (cubit) {
        expect(cubit.state, isA<FileShareLoadedFailedFile>());
      },
    );
  });
}
