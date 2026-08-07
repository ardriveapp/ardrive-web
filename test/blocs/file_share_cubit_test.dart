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

  // The ids of the design plan's example links, §1.3 - canonical, so that they
  // decode to the 32 bytes a payload stores them as.
  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeQ';
  const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';
  const bundledInTxId = 'oLd7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWc';
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

  /// What the built link actually asserts, read back out of it.
  ///
  /// The link's fields are packed into one parameter, so the only honest way to
  /// ask what a share dialog produced is to decode it - which is also what the
  /// recipient does.
  SharedFileLinkPayload payloadOf(FileShareLoadSuccess state) {
    final payload =
        SharedFileLinkPayload.tryParse(locationOf(state.fileShareLink));

    expect(payload, isNotNull, reason: 'no payload in ${state.fileShareLink}');

    return payload!;
  }

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

        expect(
          payloadOf(state),
          const SharedFileLinkPayload(
            dataTxId: dataTxId,
            metadataTxId: metadataTxId,
            ownerAddress: ownerAddress,
            name: fileName,
            size: fileSize,
            contentType: contentType,
            bundledInTxId: bundledInTxId,
            thumbnailTxId: thumbnailTxId,
          ),
        );
        expect(
          parametersOf(state).keys,
          [SharedFileLinkParams.payload],
          reason: 'a v2 link is one packed parameter and, at most, a key',
        );

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

      expect(payloadOf(state).thumbnailTxId, isNull);
      expect(payloadOf(state).dataTxId, dataTxId);
    });

    test('a file with no revision row still gets a link, without mtx',
        () async {
      await resetFile(withRevision: false);

      final state = await loaded(createCubit());

      expect(payloadOf(state).metadataTxId, isNull);
      expect(payloadOf(state).dataTxId, dataTxId);
      expect(payloadOf(state).thumbnailTxId, thumbnailTxId);
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
              (s) => payloadOf(s),
              'payload',
              isA<SharedFileLinkPayload>()
                  .having((p) => p.dataTxId, 'dataTxId', dataTxId)
                  .having((p) => p.cipher, 'cipher', isNull)
                  .having((p) => p.cipherIv, 'cipherIv', isNull),
            ),
        isA<FileShareLoadSuccess>()
            .having(
              (s) => s.isLoadingCipherDetails,
              'isLoadingCipherDetails',
              isFalse,
            )
            .having(
              (s) => payloadOf(s),
              'payload',
              isA<SharedFileLinkPayload>()
                  .having((p) => p.cipher, 'cipher', Cipher.aes256gcm)
                  .having((p) => p.cipherIv, 'cipherIv', cipherIv),
            ),
      ]),
    );

    test('the default link is keyless and the key is a separate artifact',
        () async {
      final state = await loaded(createCubit());

      expect(
        payloadOf(state),
        const SharedFileLinkPayload(
          dataTxId: dataTxId,
          metadataTxId: metadataTxId,
          ownerAddress: ownerAddress,
          name: fileName,
          size: fileSize,
          contentType: contentType,
          cipher: Cipher.aes256gcm,
          cipherIv: cipherIv,
          bundledInTxId: bundledInTxId,
          thumbnailTxId: thumbnailTxId,
        ),
      );
      expect(parametersOf(state).keys, [SharedFileLinkParams.payload]);

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
      final shownFirst = await loaded(cubit);
      final shownLength = shownFirst.fileShareLink.toString().length;

      cubit.setDetailsAreHidden(true);

      final state = cubit.state as FileShareLoadSuccess;
      final payload = payloadOf(state);

      expect(state.detailsAreHidden, isTrue);
      expect(payload.detailsAreHidden, isTrue);
      expect(payload.name, isNull);
      expect(payload.size, isNull);
      expect(payload.contentType, isNull);
      // The name is not merely unspelled: the bytes are not in the link, so
      // there is nothing for a reader of the payload to decode either.
      expect(state.fileShareLink.toString(), isNot(contains('Report')));
      expect(
        state.fileShareLink.toString().length,
        lessThan(shownLength),
      );

      // The rest of the link is untouched: hiding is not a downgrade.
      expect(payload.dataTxId, dataTxId);
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.cipherIv, cipherIv);

      cubit.setDetailsAreHidden(false);

      final shown = cubit.state as FileShareLoadSuccess;

      expect(payloadOf(shown).detailsAreHidden, isFalse);
      expect(payloadOf(shown).name, fileName);
    });

    test('pinning sets pin and leaves live links without it', () async {
      final cubit = createCubit();
      final live = await loaded(cubit);

      expect(payloadOf(live).isPinned, isFalse);

      cubit.setPinnedToCurrentVersion(true);

      final pinned = cubit.state as FileShareLoadSuccess;

      expect(pinned.isPinned, isTrue);
      expect(payloadOf(pinned).isPinned, isTrue);
      expect(payloadOf(pinned).dataTxId, dataTxId);
      expect(payloadOf(pinned).metadataTxId, metadataTxId);
    });

    test('a failed cipher lookup still yields a usable link', () async {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => throw Exception('gateway is unreachable'));

      final state = await loaded(createCubit());
      final payload = payloadOf(state);

      expect(payload.cipher, isNull);
      expect(payload.cipherIv, isNull);
      expect(state.isLoadingCipherDetails, isFalse);
      expect(state.fileKeyBase64, await expectedFileKey());

      // Everything else is still there, so the recipient pays one GraphQL
      // request at download time and nothing more (§1.2).
      expect(payload.hasFastPathTarget, isTrue);
      expect(payload.hasCipherDetails, isFalse);
      expect(payload.name, fileName);
    });

    test('a transaction without cipher tags yields a usable link', () async {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _TransactionWithTags(const {}));

      final state = await loaded(createCubit());

      expect(payloadOf(state).cipher, isNull);
      expect(payloadOf(state).dataTxId, dataTxId);
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
