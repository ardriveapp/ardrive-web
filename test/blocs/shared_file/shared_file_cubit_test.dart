import 'package:ardrive/blocs/shared_file/shared_file_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

void main() {
  const fileId = '00000000-0000-0000-0000-000000000001';
  const driveId = '00000000-0000-0000-0000-000000000002';
  const folderId = '00000000-0000-0000-0000-000000000003';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';

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
  }) {
    final entity = FileEntity(
      id: fileId,
      driveId: driveId,
      parentFolderId: folderId,
      name: name,
      size: 100,
      lastModifiedDate: createdAt,
      dataTxId: 'FxgiSM3JOAsjnZF-Yzv2z7h-Io4K6GmCarhQ0qAUL6I',
      dataContentType: 'text/plain',
    );

    entity.txId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
    entity.ownerAddress = ownerAddress;
    entity.createdAt = createdAt;

    return entity;
  }

  SharedFileCubit createCubit({
    SecretKey? fileKey,
    bool linkKeyIsDamaged = false,
  }) =>
      SharedFileCubit(
        fileId: fileId,
        fileKey: fileKey,
        linkKeyIsDamaged: linkKeyIsDamaged,
        arweave: arweave,
        licenseService: licenseService,
      );

  setUpAll(() {
    registerFallbackValue(SecretKey([]));
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
        expect(state.ownerAddress, ownerAddress);
        expect(state.fileKey, isNull);
      },
    );
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
  });
}
