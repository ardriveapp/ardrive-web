import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/shared_file/shared_file_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

const fileId = '00000000-0000-0000-0000-000000000001';
const driveId = '00000000-0000-0000-0000-000000000002';
const folderId = '00000000-0000-0000-0000-000000000003';
const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';

/// Anyone at all. The address of whoever posted the metadata transaction a
/// crafted link names - never the address that created the file.
const strangerAddress = 'Ka9pQ2xV7bN4mL8jH3gF6dS1aZ0cX5vB2nM7kJ4hG1e';

const dataTxId = 'FxgiSM3JOAsjnZF-Yzv2z7h-Io4K6GmCarhQ0qAUL6I';
const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
const otherDataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
const otherMetadataTxId = 'oLdzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBn0';

/// A metadata transaction as GraphQL hands it over.
///
/// Only the members [FileEntity.fromTransaction] and the resolver actually read
/// are implemented; anything else is a bug in the code under test.
class _FakeMetadataTransaction extends Fake implements TransactionCommonMixin {
  _FakeMetadataTransaction({
    String owner = ownerAddress,
    Map<String, String> tags = const {},
  })  : _owner = owner,
        _tags = {
          EntityTag.fileId: fileId,
          EntityTag.driveId: driveId,
          EntityTag.parentFolderId: folderId,
          EntityTag.unixTime: '1704067200',
          ...tags,
        };

  @override
  final String id = metadataTxId;

  final String _owner;
  final Map<String, String> _tags;

  @override
  TransactionCommonMixin$Owner get owner =>
      TransactionCommonMixin$Owner()..address = _owner;

  @override
  TransactionCommonMixin$Bundle? get bundledIn => null;

  @override
  List<TransactionCommonMixin$Tag> get tags => _tags.entries
      .map((entry) => TransactionCommonMixin$Tag()
        ..name = entry.key
        ..value = entry.value)
      .toList();
}

void main() {
  // A well formed base64 file key. It never decrypts anything here - the
  // arweave service is mocked - it only has to survive decodeBase64ToBytes.
  // Must be canonical base64: for a 32-byte key the final character carries
  // only 4 significant bits, so its low 2 bits must be zero or Dart's strict
  // decoder throws 'Invalid encoding before padding'.
  const fileKeyBase64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  late ArweaveService arweave;
  late LicenseService licenseService;

  FileEntity fileEntity({
    required DateTime createdAt,
    String name = 'file.txt',
    String dataTx = dataTxId,
    String metadataTx = metadataTxId,
    int size = 100,
    String owner = ownerAddress,
  }) {
    final entity = FileEntity(
      id: fileId,
      driveId: driveId,
      parentFolderId: folderId,
      name: name,
      size: size,
      lastModifiedDate: createdAt,
      dataTxId: dataTx,
      dataContentType: 'text/plain',
    );

    entity.txId = metadataTx;
    entity.ownerAddress = owner;
    entity.createdAt = createdAt;

    return entity;
  }

  /// The metadata JSON a file's metadata transaction carries.
  Uint8List metadataJson({
    String name = 'file.txt',
    int size = 100,
    String dataTx = dataTxId,
    String contentType = 'text/plain',
  }) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'name': name,
        'size': size,
        'lastModifiedDate': DateTime(2024, 1, 1).millisecondsSinceEpoch,
        'dataTxId': dataTx,
        'dataContentType': contentType,
      })));

  /// A v2 payload with every field a share link embeds by default.
  ///
  /// Pass `null` for a field to model a link that never carried it - or that
  /// carried it malformed, since the parser drops such a field and hands the
  /// resolver the same `null` either way.
  SharedFileLinkPayload v2Payload({
    String? dataTx = dataTxId,
    String? metadataTx = metadataTxId,
    String? owner = ownerAddress,
    String? name = 'file.txt',
    int? size = 100,
    String? contentType = 'text/plain',
    String? cipher,
    String? cipherIv,
    bool isPinned = false,
    SharedFileLinkKey key = SharedFileLinkKey.absent,
  }) =>
      SharedFileLinkPayload(
        dataTxId: dataTx,
        metadataTxId: metadataTx,
        ownerAddress: owner,
        name: name,
        size: size,
        contentType: contentType,
        cipher: cipher,
        cipherIv: cipherIv,
        isPinned: isPinned,
        key: key,
      );

  SharedFileCubit createCubit({
    String id = fileId,
    SecretKey? fileKey,
    bool linkKeyIsDamaged = false,
    SharedFileLinkPayload? payload,
    ArDriveCrypto? crypto,
  }) =>
      SharedFileCubit(
        fileId: id,
        fileKey: fileKey,
        linkKeyIsDamaged: linkKeyIsDamaged,
        linkPayload: payload,
        arweave: arweave,
        licenseService: licenseService,
        crypto: crypto,
        // The propagation retries are the behavior under test, not the wait.
        propagationRetryDelay: Duration.zero,
      );

  setUpAll(() {
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(_FakeMetadataTransaction());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    arweave = MockArweaveService();
    licenseService = MockLicenseService();
  });

  group('SharedFileCubit load', () {
    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileLoadFailure when looking the file up fails',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => throw Exception('gateway is unreachable'));

        return createCubit();
      },
      expect: () => [isA<SharedFileLoadFailure>()],
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileLoadFailure when fetching the file entities fails',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.public);
        when(() => arweave.getAllFileEntitiesWithId(any(), any()))
            .thenAnswer((_) async => throw Exception('gateway is unreachable'));

        return createCubit();
      },
      expect: () => [isA<SharedFileLoadFailure>()],
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileNotFound when no file with the shared id exists',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => null);
        when(() => arweave.getAllFileEntitiesWithId(any(), any()))
            .thenAnswer((_) async => null);

        return createCubit();
      },
      expect: () => [isA<SharedFileNotFound>()],
      verify: (cubit) {
        final state = cubit.state as SharedFileNotFound;

        // A v1 link asserts nothing, so an empty owner probe is the file not
        // existing and is never dressed up as a file that is still spreading.
        expect(state.mayStillBePropagating, isFalse);
        expect(state.retryAttempt, 0);
      },
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileKeyInvalid, and never SharedFileNotFound, when the key '
      'in the link cannot decrypt the file',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.private);
        // Every revision failed to decrypt and was skipped, which the service
        // reports the same way it reports a missing file.
        when(() => arweave.getAllFileEntitiesWithId(any(), any()))
            .thenAnswer((_) async => null);

        return createCubit(fileKey: SecretKey(List.filled(32, 1)));
      },
      expect: () => [isA<SharedFileKeyInvalid>()],
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileIsPrivate when the link carries no key',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.private);

        return createCubit();
      },
      expect: () => [isA<SharedFileIsPrivate>()],
      verify: (_) {
        verifyNever(() => arweave.getAllFileEntitiesWithId(any(), any()));
      },
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileKeyInvalid flagged as damaged when the key in the link '
      'could not be decoded',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.private);

        // The route parser dropped the mangled key, so the cubit gets no key -
        // only the flag saying one was sent and arrived broken.
        return createCubit(linkKeyIsDamaged: true);
      },
      expect: () => [isA<SharedFileKeyInvalid>()],
      verify: (cubit) {
        final state = cubit.state as SharedFileKeyInvalid;

        expect(state.linkKeyIsDamaged, isTrue);
        // Nothing was worth fetching: there is no key to try.
        verifyNever(() => arweave.getAllFileEntitiesWithId(any(), any()));
      },
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'ignores a damaged link key when the file turns out to be public',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.public);
        when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
          (_) async => [fileEntity(createdAt: DateTime(2024, 1, 1))],
        );

        return createCubit(linkKeyIsDamaged: true);
      },
      // A public file needs no key, so a damaged one changes nothing.
      expect: () => [isA<SharedFileLoadSuccess>()],
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'emits SharedFileLoadSuccess with the revisions of a valid public link',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.public);
        when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
          (_) async => [
            fileEntity(createdAt: DateTime(2024, 1, 1), name: 'first.txt'),
            fileEntity(createdAt: DateTime(2024, 1, 2), name: 'latest.txt'),
          ],
        );

        return createCubit();
      },
      expect: () => [isA<SharedFileLoadSuccess>()],
      verify: (cubit) {
        final state = cubit.state as SharedFileLoadSuccess;

        expect(state.fileRevisions.length, 2);
        // Revisions are in reverse chronological order.
        expect(state.fileRevisions.first.name, 'latest.txt');
        // F1: the page downloads what its header describes - the newest
        // revision - and never the original bytes.
        expect(state.revision.name, 'latest.txt');
        expect(state.ownerAddress, ownerAddress);
        expect(state.fileKey, isNull);
      },
    );

    blocTest<SharedFileCubit, SharedFileState>(
      'a v1 link resolves over GraphQL and nothing else',
      build: () {
        when(() => arweave.getFilePrivacyForId(any()))
            .thenAnswer((_) async => DrivePrivacyTag.public);
        when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
          (_) async => [fileEntity(createdAt: DateTime(2024, 1, 1))],
        );

        return createCubit();
      },
      expect: () => [isA<SharedFileLoadSuccess>()],
      verify: (cubit) {
        final state = cubit.state as SharedFileLoadSuccess;

        // Today's two calls, and not one of the payload-driven ones: a link
        // that claims nothing gets checked against nothing, and its history is
        // already in hand.
        verify(() => arweave.getFilePrivacyForId(any())).called(1);
        verify(() => arweave.getAllFileEntitiesWithId(any(), any())).called(1);
        verifyNever(() => arweave.getTransactionDetails(any()));
        verifyNever(() => arweave.getLatestFileEntityWithId(any(), any()));

        expect(state.payload, isNull);
        expect(state.verification, LinkVerification.unavailable);
        expect(state.newerVersionAvailable, isFalse);
        expect(state.activityStatus, SharedFileActivityStatus.loaded);
      },
    );
  });

  group('SharedFileCubit v2 fast path', () {
    test('paints a complete payload without a single request', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload());

      // The paint happens while the constructor runs: no await, no request.
      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.revision.dataTxId, dataTxId);
      expect(state.revision.name, 'file.txt');
      expect(state.revision.size, 100);
      expect(state.revision.dataContentType, 'text/plain');
      expect(state.ownerAddress, ownerAddress);
      expect(state.verification, LinkVerification.pending);
      expect(state.detailsAreResolved, isFalse);

      verifyZeroInteractions(arweave);

      await cubit.backgroundWork;
    });

    test('locks a private link that carries no key, without a request',
        () async {
      final cubit = createCubit(
        payload: v2Payload(cipher: 'AES256-GCM', cipherIv: '9tR2kX0pLmQz'),
      );

      final state = cubit.state as SharedFileIsPrivate;

      // The locked card shows what the link embedded.
      expect(state.payload?.name, 'file.txt');
      verifyZeroInteractions(arweave);
    });

    test('reports a damaged key on a private link, without a request',
        () async {
      final cubit = createCubit(
        linkKeyIsDamaged: true,
        payload: v2Payload(cipher: 'AES256-GCM', cipherIv: '9tR2kX0pLmQz'),
      );

      final state = cubit.state as SharedFileKeyInvalid;

      expect(state.linkKeyIsDamaged, isTrue);
      expect(state.payload?.name, 'file.txt');
      // No query recovers a file key. Asking the network for one would be
      // pointless, so nothing is asked.
      verifyZeroInteractions(arweave);
    });

    test('paints a link with no name or size, then fills them in', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(
        payload: v2Payload(name: null, size: null, contentType: null),
      );

      final painted = cubit.state as SharedFileLoadSuccess;

      // Placeholders, flagged as such, and still no request.
      expect(painted.revision.name, isEmpty);
      expect(painted.revision.size, 0);
      expect(painted.detailsAreResolved, isFalse);
      verifyZeroInteractions(arweave);

      await cubit.backgroundWork;

      final resolved = cubit.state as SharedFileLoadSuccess;

      expect(resolved.revision.name, 'file.txt');
      expect(resolved.revision.size, 100);
      expect(resolved.detailsAreResolved, isTrue);
      // A link that claimed nothing about the name cannot have lied about it.
      expect(resolved.verification, LinkVerification.verified);
    });

    test('never probes the first writer when the link names the owner',
        () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload());

      await cubit.backgroundWork;

      verifyNever(() => arweave.getOwnerForFileEntityWithId(any()));
      verifyNever(() => arweave.getFilePrivacyForId(any()));
    });
  });

  group('SharedFileCubit v2 verification', () {
    test('verifies a link against the file\'s own record', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload());

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.verification, LinkVerification.verified);
      expect(state.revision.dataTxId, dataTxId);
      expect(state.detailsAreResolved, isTrue);
      expect(state.newerVersionAvailable, isFalse);
    });

    test('takes the file\'s record over a link that disagrees with it',
        () async {
      // Same revision, different bytes: the link is asserting a data
      // transaction that is not the one this revision names.
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(
          createdAt: DateTime(2024, 1, 1),
          dataTx: otherDataTxId,
        ),
      );

      final cubit = createCubit(payload: v2Payload());

      expect(
        (cubit.state as SharedFileLoadSuccess).revision.dataTxId,
        dataTxId,
      );

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.verification, LinkVerification.mismatch);
      // What the file says it is, not what the link said it was.
      expect(state.revision.dataTxId, otherDataTxId);
      // The link's claims stay on the state so the UI can say what changed.
      expect(state.payload?.dataTxId, dataTxId);
    });

    test('cannot verify a link that carries no metadata transaction', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload(metadataTx: null));

      expect(
        (cubit.state as SharedFileLoadSuccess).verification,
        LinkVerification.unavailable,
      );

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.verification, LinkVerification.unavailable);
      // Nothing to fetch a verdict from.
      verifyNever(() => arweave.getTransactionDetails(any()));
      // The details still get resolved: the revision was found by its data
      // transaction, so the header stops being a placeholder.
      expect(state.detailsAreResolved, isTrue);
    });

    test('cannot verify a link whose metadata will not load', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => throw Exception('gateway is unreachable'));
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => throw Exception('gateway is unreachable'));

      final cubit = createCubit(payload: v2Payload());

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      // The page the link painted survives a failed check.
      expect(state.verification, LinkVerification.unavailable);
      expect(state.revision.dataTxId, dataTxId);
    });

    /// The metadata transaction a link names is fetched **by id**, and anyone
    /// can post a transaction. A stranger who knows a circulating file id can
    /// post ArFS metadata tagged with it, point its `Data-Tx-Id` at their own
    /// bytes, and send a link whose every field agrees with that metadata. The
    /// only thing that tells that apart from the real thing is who wrote it.
    ///
    /// The forgery below is deliberately self-consistent: the link and the
    /// metadata agree on the name, the size, the type, the data transaction
    /// and even the owner. Nothing but the authorship check stands between it
    /// and an affirmative badge over a stranger's bytes.
    void forgedMetadataFrom(String stranger) {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _FakeMetadataTransaction(owner: stranger));
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => metadataJson());
      // What the file itself says, once the forgery has been rejected.
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.public);
      when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
        (_) async => [
          fileEntity(
            createdAt: DateTime(2024, 2, 1),
            dataTx: otherDataTxId,
            metadataTx: otherMetadataTxId,
            name: 'the-real-file.txt',
          ),
        ],
      );
    }

    test('never verifies metadata the file\'s owner did not write', () async {
      // The file has moved on since the link was made, which is what sends the
      // check to the metadata transaction the link names rather than to the
      // newest revision.
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(
          createdAt: DateTime(2024, 2, 1),
          dataTx: otherDataTxId,
          metadataTx: otherMetadataTxId,
          name: 'the-real-file.txt',
        ),
      );
      forgedMetadataFrom(strangerAddress);

      final cubit = createCubit(payload: v2Payload(owner: strangerAddress));

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      // A forged link is a mismatch, and can never be the green check.
      expect(state.verification, LinkVerification.mismatch);
      // And the page ends up on the file's own bytes, not the stranger's.
      expect(state.revision.dataTxId, otherDataTxId);
      expect(state.revision.name, 'the-real-file.txt');
    });

    test('probes the first writer when nothing else has said who owns the file',
        () async {
      // The newest revision could not be read, so the owner-scoped query
      // answered nothing. The first-writer probe is what is left, and it is the
      // same one every GraphQL path already makes.
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => null);
      when(() => arweave.getOwnerForFileEntityWithId(any()))
          .thenAnswer((_) async => ownerAddress);
      forgedMetadataFrom(strangerAddress);

      final cubit = createCubit(payload: v2Payload(owner: strangerAddress));

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.verification, LinkVerification.mismatch);
      verify(() => arweave.getOwnerForFileEntityWithId(fileId)).called(1);
    });

    test('resolves the owner behind the paint, never in front of it', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => null);
      when(() => arweave.getOwnerForFileEntityWithId(any()))
          .thenAnswer((_) async => ownerAddress);
      forgedMetadataFrom(strangerAddress);

      final cubit = createCubit(payload: v2Payload(owner: strangerAddress));

      // The paint happened while the constructor ran, authorship check and all.
      expect(cubit.state, isA<SharedFileLoadSuccess>());
      verifyZeroInteractions(arweave);

      await cubit.backgroundWork;
    });

    test('does not verify a link that asserted nothing to verify', () async {
      // `?v=2&mtx=...` and not one field more. Everything the page shows was
      // resolved from the chain, so there is nothing the link could have been
      // right or wrong about.
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _FakeMetadataTransaction());
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => metadataJson());
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(
        payload: v2Payload(
          dataTx: null,
          owner: null,
          name: null,
          size: null,
          contentType: null,
        ),
      );

      await expectLater(
        cubit.stream,
        emitsThrough(isA<SharedFileLoadSuccess>()),
      );

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.verification, LinkVerification.unavailable);
    });
  });

  group('SharedFileCubit v2 freshness', () {
    test('offers a newer revision without changing the target', () async {
      // The newest revision is not the one the link shared.
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(
          createdAt: DateTime(2024, 2, 1),
          dataTx: otherDataTxId,
          metadataTx: otherMetadataTxId,
          name: 'newer.txt',
        ),
      );
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _FakeMetadataTransaction());
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => metadataJson());

      final cubit = createCubit(payload: v2Payload(isPinned: true));

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.newerVersionAvailable, isTrue);
      expect(state.isPinned, isTrue);
      // Offered, never swapped: the bytes stay the ones that were shared.
      expect(state.revision.dataTxId, dataTxId);
      expect(state.revision.name, 'file.txt');
      expect(state.verification, LinkVerification.verified);
    });
  });

  group('SharedFileCubit v2 fallbacks', () {
    test('resolves the shared revision from mtx when dtx did not survive',
        () async {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _FakeMetadataTransaction());
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => metadataJson());
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload(dataTx: null));

      await expectLater(
        cubit.stream,
        emitsThrough(isA<SharedFileLoadSuccess>()),
      );

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.revision.dataTxId, dataTxId);
      expect(state.detailsAreResolved, isTrue);
      // One lookup by id - not the owner probe and revision enumeration a v1
      // link would have paid for.
      verify(() => arweave.getTransactionDetails(metadataTxId)).called(1);
      verifyNever(() => arweave.getFilePrivacyForId(any()));
      verifyNever(() => arweave.getAllFileEntitiesWithId(any(), any()));

      await cubit.backgroundWork;
    });

    test('falls back to the v1 path when nothing usable survived the payload',
        () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.public);
      when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
        (_) async => [fileEntity(createdAt: DateTime(2024, 1, 1))],
      );

      final cubit = createCubit(
        payload: v2Payload(dataTx: null, metadataTx: null),
      );

      await expectLater(
        cubit.stream,
        emitsThrough(isA<SharedFileLoadSuccess>()),
      );

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.revision.dataTxId, dataTxId);
      expect(state.verification, LinkVerification.unavailable);
      verify(() => arweave.getFilePrivacyForId(any())).called(1);
      verify(() => arweave.getAllFileEntitiesWithId(any(), any())).called(1);
    });

    test('locks a link that corroborates nothing and turns out to be private',
        () async {
      // Neither `c` nor `mtx` survived, and no key came with the link, so the
      // page painted as if the file were public. Nothing but the file id is
      // left to tell the difference.
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => null);
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);

      final cubit = createCubit(payload: v2Payload(metadataTx: null));

      expect(cubit.state, isA<SharedFileLoadSuccess>());

      await cubit.backgroundWork;

      expect(cubit.state, isA<SharedFileIsPrivate>());
    });

    test('locks a link whose metadata turns out to be encrypted', () async {
      // The link never said the file was private - `c` was absent, or arrived
      // malformed and was dropped - so the page painted. Its metadata says
      // otherwise.
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => null);
      when(() => arweave.getTransactionDetails(any())).thenAnswer(
        (_) async => _FakeMetadataTransaction(
          tags: const {EntityTag.cipherIv: 'nZ4t6xM3aQ8pLwRt'},
        ),
      );

      final cubit = createCubit(payload: v2Payload());

      expect(cubit.state, isA<SharedFileLoadSuccess>());

      await cubit.backgroundWork;

      expect(cubit.state, isA<SharedFileIsPrivate>());
      // The metadata was never fetched: its tags already said it is encrypted.
      verifyNever(
        () => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')),
      );
    });
  });

  group('SharedFileCubit not yet mined', () {
    test('retries a file the link says exists, then settles into not found',
        () async {
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => null);
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => null);
      when(() => arweave.getAllFileEntitiesWithId(any(), any()))
          .thenAnswer((_) async => null);

      final cubit = createCubit(payload: v2Payload(dataTx: null));

      await expectLater(
        cubit.stream,
        emitsInOrder([
          isA<SharedFileNotFound>()
              .having((s) => s.retryAttempt, 'retryAttempt', 1)
              .having((s) => s.mayStillBePropagating, 'propagating', isTrue),
          isA<SharedFileNotFound>()
              .having((s) => s.retryAttempt, 'retryAttempt', 2)
              .having((s) => s.mayStillBePropagating, 'propagating', isTrue),
          isA<SharedFileNotFound>()
              .having((s) => s.retryAttempt, 'retryAttempt', 3)
              .having((s) => s.mayStillBePropagating, 'propagating', isTrue),
          isA<SharedFileNotFound>()
              .having((s) => s.retryAttempt, 'retryAttempt', 3)
              .having((s) => s.mayStillBePropagating, 'propagating', isFalse),
        ]),
      );

      // One resolution, then one per retry.
      verify(() => arweave.getAllFileEntitiesWithId(any(), any())).called(4);
    });
  });

  group('SharedFileCubit damaged link', () {
    test('answers a link that names no file at all without a request', () {
      // `/file//view`: `Uri.pathSegments` keeps the empty segment, so the route
      // parser hands the page an empty file id. No query can be built from it.
      final cubit = createCubit(id: '');

      expect(cubit.state, isA<SharedFileLinkDamaged>());
      verifyZeroInteractions(arweave);
    });

    test('stays damaged when the load is run again', () async {
      final cubit = createCubit(id: '   ');

      await cubit.retry();

      expect(cubit.state, isA<SharedFileLinkDamaged>());
      verifyZeroInteractions(arweave);
    });
  });

  group('SharedFileCubit newest revision', () {
    /// A pinned link on a file that has moved on since it was shared.
    SharedFileCubit onAnOlderRevision() {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(
          createdAt: DateTime(2024, 2, 1),
          dataTx: otherDataTxId,
          metadataTx: otherMetadataTxId,
          name: 'newer.txt',
        ),
      );
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) async => _FakeMetadataTransaction());
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => metadataJson());

      return createCubit(payload: v2Payload(isPinned: true));
    }

    test('adopts the newest revision only when it is asked to', () async {
      final cubit = onAnOlderRevision();

      await cubit.backgroundWork;

      final offered = cubit.state as SharedFileLoadSuccess;

      // The freshness check offered; it did not swap.
      expect(offered.newerVersionAvailable, isTrue);
      expect(offered.revision.dataTxId, dataTxId);
      expect(offered.showsLatestRevision, isFalse);

      await cubit.showLatestRevision();

      final latest = cubit.state as SharedFileLoadSuccess;

      expect(latest.revision.dataTxId, otherDataTxId);
      expect(latest.revision.name, 'newer.txt');
      expect(latest.showsLatestRevision, isTrue);
      // The offer has been taken, so there is nothing left to offer.
      expect(latest.newerVersionAvailable, isFalse);
      // What the link shared is remembered, so the version history can keep
      // marking it and the page can go back to it.
      expect(latest.sharedRevision.dataTxId, dataTxId);
      expect(latest.linkRevision?.metadataTxId, metadataTxId);
      // The verdict is about the link, and the recipient's own choice does not
      // turn the link into a liar.
      expect(latest.verification, LinkVerification.verified);
      expect(latest.isPinned, isTrue);
      expect(latest.detailsAreResolved, isTrue);
    });

    test('puts the revision the link named back', () async {
      final cubit = onAnOlderRevision();

      await cubit.backgroundWork;
      await cubit.showLatestRevision();
      await cubit.showSharedRevision();

      final shared = cubit.state as SharedFileLoadSuccess;

      // A pinned link is never a one-way door.
      expect(shared.revision.dataTxId, dataTxId);
      expect(shared.revision.name, 'file.txt');
      expect(shared.showsLatestRevision, isFalse);
      // And the newer revision is on offer again.
      expect(shared.newerVersionAvailable, isTrue);
      expect(shared.sharedRevision.dataTxId, dataTxId);
    });

    test('does nothing when no newer revision is on offer', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload());

      await cubit.backgroundWork;

      final before = cubit.state;

      await cubit.showLatestRevision();

      expect(cubit.state, before);
      // The one lookup the background work already made, and no other.
      verify(() => arweave.getLatestFileEntityWithId(any(), any())).called(1);
    });

    test('is not undone by a background check that finishes after it',
        () async {
      final metadata = Completer<TransactionCommonMixin?>();

      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(
          createdAt: DateTime(2024, 2, 1),
          dataTx: otherDataTxId,
          metadataTx: otherMetadataTxId,
          name: 'newer.txt',
        ),
      );
      // The link's own metadata is still in flight when the recipient presses.
      when(() => arweave.getTransactionDetails(any()))
          .thenAnswer((_) => metadata.future);
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => metadataJson());

      final cubit = createCubit(payload: v2Payload());

      await expectLater(
        cubit.stream,
        emitsThrough(
          isA<SharedFileLoadSuccess>().having(
            (state) => state.newerVersionAvailable,
            'newerVersionAvailable',
            isTrue,
          ),
        ),
      );

      await cubit.showLatestRevision();

      metadata.complete(_FakeMetadataTransaction());

      await cubit.backgroundWork;

      final state = cubit.state as SharedFileLoadSuccess;

      // The recipient's choice outranks work that started before it.
      expect(state.revision.dataTxId, otherDataTxId);
      expect(state.showsLatestRevision, isTrue);
      expect(state.newerVersionAvailable, isFalse);
      // The verdict on the link still lands.
      expect(state.verification, LinkVerification.verified);
    });

    test('leaves the offer standing when the newest revision cannot be read',
        () async {
      final cubit = onAnOlderRevision();

      await cubit.backgroundWork;

      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => throw Exception('gateway is unreachable'));

      await cubit.showLatestRevision();

      final state = cubit.state as SharedFileLoadSuccess;

      // Nothing was swapped in, nothing is spinning, and pressing again tries
      // again.
      expect(state.revision.dataTxId, dataTxId);
      expect(state.showsLatestRevision, isFalse);
      expect(state.newerVersionAvailable, isTrue);
    });
  });

  group('SharedFileCubit activity', () {
    test('does not load the revision history until it is asked for', () async {
      var historyFetches = 0;

      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );
      when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
        (_) async {
          historyFetches++;

          return [
            fileEntity(createdAt: DateTime(2024, 1, 1), name: 'first.txt'),
            fileEntity(createdAt: DateTime(2024, 1, 2), name: 'file.txt'),
          ];
        },
      );

      final cubit = createCubit(payload: v2Payload());

      await cubit.backgroundWork;

      final painted = cubit.state as SharedFileLoadSuccess;

      expect(painted.activityStatus, SharedFileActivityStatus.notLoaded);
      expect(painted.activityRevisions, isEmpty);
      // The dominant cost of the first paint today, and it is not paid here.
      expect(historyFetches, 0);
      verifyNever(() => arweave.getAllFileEntitiesWithId(any(), any()));

      await cubit.loadActivity();

      final loaded = cubit.state as SharedFileLoadSuccess;

      expect(loaded.activityStatus, SharedFileActivityStatus.loaded);
      expect(loaded.activityRevisions.length, 2);
      // The history is history: the download target is untouched by it.
      expect(loaded.revision.dataTxId, painted.revision.dataTxId);
      expect(historyFetches, 1);

      // Asking twice fetches once.
      await cubit.loadActivity();

      expect(historyFetches, 1);
    });
  });

  group('SharedFileCubit recoverMissingData', () {
    test('adopts the file\'s real data transaction when the link\'s is gone',
        () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload(metadataTx: null));

      await cubit.backgroundWork;

      // The file's record names other bytes than the link did.
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(
          createdAt: DateTime(2024, 1, 1),
          dataTx: otherDataTxId,
        ),
      );

      await cubit.recoverMissingData();

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.revision.dataTxId, otherDataTxId);
      expect(state.verification, LinkVerification.mismatch);
    });

    test('retries when the file agrees with the link, then settles', () async {
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );

      final cubit = createCubit(payload: v2Payload(metadataTx: null));

      await cubit.backgroundWork;

      await cubit.recoverMissingData();

      final state = cubit.state as SharedFileNotFound;

      expect(state.retryAttempt, SharedFileCubit.maxPropagationRetries);
      expect(state.mayStillBePropagating, isFalse);
    });
  });

  group('SharedFileCubit retry', () {
    test('runs the load again after a failure', () async {
      var attempts = 0;

      when(() => arweave.getFilePrivacyForId(any())).thenAnswer((_) async {
        attempts++;

        if (attempts == 1) {
          throw Exception('gateway is unreachable');
        }

        return DrivePrivacyTag.private;
      });

      final cubit = createCubit();

      await expectLater(
        cubit.stream,
        emitsThrough(isA<SharedFileLoadFailure>()),
      );

      await cubit.retry();

      expect(cubit.state, isA<SharedFileIsPrivate>());
      expect(attempts, 2);
    });

    test('runs the load again with the key that was last submitted', () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => throw Exception('gateway is unreachable'));

      final cubit = createCubit();

      await expectLater(cubit.stream, emitsThrough(isA<SharedFileIsPrivate>()));

      await cubit.submit(fileKeyBase64);

      expect(cubit.state, isA<SharedFileLoadFailure>());

      when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
        (_) async => [fileEntity(createdAt: DateTime(2024, 1, 1))],
      );

      await cubit.retry();

      final state = cubit.state as SharedFileLoadSuccess;
      expect(state.fileKey, isNotNull);
    });
  });

  group('SharedFileCubit submit', () {
    test('emits SharedFileKeyInvalid when the typed key does not unlock it',
        () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => null);

      final cubit = createCubit();

      await expectLater(cubit.stream, emitsThrough(isA<SharedFileIsPrivate>()));

      await cubit.submit(fileKeyBase64);

      expect(cubit.state, isA<SharedFileKeyInvalid>());
    });

    test('emits SharedFileKeyInvalid when the typed key is malformed',
        () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);

      final cubit = createCubit();

      await expectLater(cubit.stream, emitsThrough(isA<SharedFileIsPrivate>()));

      await cubit.submit('not a valid key!');

      expect(cubit.state, isA<SharedFileKeyInvalid>());
      verifyNever(() => arweave.getLatestFileEntityWithId(any(), any()));
    });

    test('loads the file details when the typed key unlocks the file',
        () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );
      when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
        (_) async => [fileEntity(createdAt: DateTime(2024, 1, 1))],
      );

      final cubit = createCubit();

      await expectLater(cubit.stream, emitsThrough(isA<SharedFileIsPrivate>()));

      await cubit.submit(fileKeyBase64);

      final state = cubit.state as SharedFileLoadSuccess;
      expect(state.fileRevisions.single.fileId, fileId);
      expect(state.fileKey, isNotNull);
    });

    test('unlocks a damaged link when a working key is typed', () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );
      when(() => arweave.getAllFileEntitiesWithId(any(), any())).thenAnswer(
        (_) async => [fileEntity(createdAt: DateTime(2024, 1, 1))],
      );

      final cubit = createCubit(linkKeyIsDamaged: true);

      await expectLater(
        cubit.stream,
        emitsThrough(isA<SharedFileKeyInvalid>()),
      );

      // The damaged link flag must not lock the recipient out: the key they
      // were sent separately still works.
      await cubit.submit(fileKeyBase64);

      final state = cubit.state as SharedFileLoadSuccess;
      expect(state.fileRevisions.single.fileId, fileId);
      expect(state.fileKey, isNotNull);
    });

    test('stops reporting a damaged link once a key has been typed', () async {
      when(() => arweave.getFilePrivacyForId(any()))
          .thenAnswer((_) async => DrivePrivacyTag.private);
      when(() => arweave.getLatestFileEntityWithId(any(), any()))
          .thenAnswer((_) async => null);

      final cubit = createCubit(linkKeyIsDamaged: true);

      await expectLater(
        cubit.stream,
        emitsThrough(isA<SharedFileKeyInvalid>()),
      );
      expect((cubit.state as SharedFileKeyInvalid).linkKeyIsDamaged, isTrue);

      await cubit.submit(fileKeyBase64);

      // The typed key was decoded and simply did not work, which is a
      // different message from "the link arrived damaged".
      final state = cubit.state as SharedFileKeyInvalid;
      expect(state.linkKeyIsDamaged, isFalse);
    });

    test('tries a typed key against the revision the link names', () async {
      final crypto = MockArDriveCrypto();

      when(() => arweave.getTransactionDetails(any())).thenAnswer(
        (_) async => _FakeMetadataTransaction(
          tags: const {
            EntityTag.cipher: 'AES256-GCM',
            EntityTag.cipherIv: 'nZ4t6xM3aQ8pLwRt',
          },
        ),
      );
      when(() => arweave.getEntityDataFromNetwork(txId: any(named: 'txId')))
          .thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
      when(() => arweave.getLatestFileEntityWithId(any(), any())).thenAnswer(
        (_) async => fileEntity(createdAt: DateTime(2024, 1, 1)),
      );
      when(() => crypto.decryptEntityJson(any(), any(), any()))
          .thenAnswer((_) async => throw Exception('wrong key'));

      final cubit = createCubit(
        crypto: crypto,
        payload: v2Payload(cipher: 'AES256-GCM', cipherIv: '9tR2kX0pLmQz'),
      );

      expect(cubit.state, isA<SharedFileIsPrivate>());

      await cubit.submit(fileKeyBase64);

      expect(cubit.state, isA<SharedFileKeyInvalid>());
      // The key was tried against the shared revision itself, not against a
      // revision list the owner probe would have had to find first.
      verify(() => arweave.getTransactionDetails(metadataTxId)).called(1);
      verifyNever(() => arweave.getFilePrivacyForId(any()));

      // A key that works opens the same door.
      when(() => crypto.decryptEntityJson(any(), any(), any())).thenAnswer(
        (_) async =>
            jsonDecode(utf8.decode(metadataJson())) as Map<String, dynamic>,
      );

      await cubit.submit(fileKeyBase64);

      final state = cubit.state as SharedFileLoadSuccess;

      expect(state.fileKey, isNotNull);
      expect(state.revision.dataTxId, dataTxId);

      await cubit.backgroundWork;
    });
  });
}
