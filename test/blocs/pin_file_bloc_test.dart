import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class MockFileIdResolver extends Mock implements FileIdResolver {}

class MockTurboUploadService extends Mock implements TurboUploadService {}

class MockProfileCubit extends MockCubit<ProfileState>
    implements ProfileCubit {}

void main() {
  group('PinFileBloc', () {
    final FileIdResolver fileIdResolver = MockFileIdResolver();
    final ArweaveService arweave = MockArweaveService();
    final TurboUploadService turboService = MockTurboUploadService();
    final ProfileCubit profileCubit = MockProfileCubit();
    final DriveDao driveDao = MockDriveDao();

    const String validName = 'Ñoquis con tuco 🍝😋';
    const String validTxId_1 = 'HelloHelloHelloHelloHelloHelloHelloH-+_ABCD';
    const String validTxId_2 = '+_-1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcd';
    const String validFileId_1 = '01234567-89ab-cdef-0123-456789abcdef';
    const String validFileId_2 = '00000000-0000-0000-0000-000000000000';
    const String stubOwner = '0000000000000000000000000000000000000000000';
    const String stubDriveId = '00000000-0000-0000-0000-000000000000';
    const String stubFolderId = '00000000-0000-0000-0000-000000000001';

    const String invalidName = ' Buseca.mp3 🍛🤢 ';
    const String invalidId = 'not a tx id neither a file id';

    final DateTime mockDate = DateTime(1234567);

    setUp(() {
      when(() => fileIdResolver.requestForTransactionId(validTxId_1))
          .thenAnswer(
        (_) async => ResolveIdResult(
          privacy: DrivePrivacy.public,
          maybeName: null,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
          pinnedDataOwnerAddress: stubOwner,
        ),
      );
      when(() => fileIdResolver.requestForTransactionId(validTxId_2))
          .thenAnswer(
        (_) async => ResolveIdResult(
          privacy: DrivePrivacy.public,
          maybeName: null,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_2,
          pinnedDataOwnerAddress: stubOwner,
        ),
      );
      when(() => fileIdResolver.requestForFileId(validFileId_1)).thenAnswer(
        (_) async => ResolveIdResult(
          privacy: DrivePrivacy.public,
          maybeName: validName,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
          pinnedDataOwnerAddress: stubOwner,
        ),
      );
      when(() => fileIdResolver.requestForFileId(validFileId_2)).thenAnswer(
        (_) async => ResolveIdResult(
          privacy: DrivePrivacy.public,
          maybeName: validName,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_2,
          pinnedDataOwnerAddress: stubOwner,
        ),
      );
      when(() => driveDao.doesEntityWithNameExist(
            name: validName,
            driveId: stubDriveId,
            parentFolderId: stubFolderId,
          )).thenAnswer((invocation) => Future.value(false));
      when(() => driveDao.doesEntityWithNameExist(
            name: 'otro nombre',
            driveId: stubDriveId,
            parentFolderId: stubFolderId,
          )).thenAnswer((invocation) => Future.value(false));
      when(() => driveDao.doesEntityWithNameExist(
            name: 'pew! pew! pew!',
            driveId: stubDriveId,
            parentFolderId: stubFolderId,
          )).thenAnswer((invocation) => Future.value(false));
    });

    blocTest<PinFileBloc, PinFileState>(
      'initial state',
      build: () => PinFileBloc(
        fileIdResolver: fileIdResolver,
        arweave: arweave,
        turboUploadService: turboService,
        profileCubit: profileCubit,
        driveDao: driveDao,
        driveID: stubDriveId,
        parentFolderId: stubFolderId,
      ),
      act: (bloc) => bloc
        ..add(
          const FieldsChanged(name: '', id: ''),
        ),
      expect: () => [const PinFileInitial()],
    );

    group('fields synchronous validation', () {
      blocTest<PinFileBloc, PinFileState>(
        'for a valid transaction id',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: validName, id: validTxId_1),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validTxId_1,
            name: validName,
            idValidation: IdValidationResult.validTransactionId,
            nameValidation: NameValidationResult.valid,
          ),
          PinFileFieldsValid(
            id: validTxId_1,
            name: validName,
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.validTransactionId,
            privacy: DrivePrivacy.public,
            dataContentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
            pinnedDataOwnerAddress: stubOwner,
          ),
        ],
      );

      blocTest(
        'for a valid file id',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: validName, id: validFileId_1),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: validName,
            idValidation: IdValidationResult.validEntityId,
            nameValidation: NameValidationResult.valid,
          ),
          PinFileFieldsValid(
            id: validFileId_1,
            name: validName,
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.validEntityId,
            privacy: DrivePrivacy.public,
            dataContentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
            pinnedDataOwnerAddress: stubOwner,
          ),
        ],
      );

      blocTest(
        'for an invalid name but valid id',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: invalidName, id: validTxId_1),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validTxId_1,
            name: invalidName,
            nameValidation: NameValidationResult.invalid,
            idValidation: IdValidationResult.validTransactionId,
          ),
          PinFileFieldsValid(
            id: validTxId_1,
            name: invalidName,
            nameValidation: NameValidationResult.invalid,
            idValidation: IdValidationResult.validTransactionId,
            privacy: DrivePrivacy.public,
            dataContentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
            pinnedDataOwnerAddress: stubOwner,
          ),
        ],
      );

      blocTest(
        'for an empty name and valid file id',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: '', id: validFileId_1),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: '',
            nameValidation: NameValidationResult.initial,
            idValidation: IdValidationResult.validEntityId,
          ),
          PinFileFieldsValid(
            id: validFileId_1,
            name: validName,
            nameValidation: NameValidationResult.initial,
            idValidation: IdValidationResult.validEntityId,
            privacy: DrivePrivacy.public,
            dataContentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
            pinnedDataOwnerAddress: stubOwner,
          ),
        ],
      );

      blocTest(
        'for an invalid id',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: validName, id: invalidId),
          ),
        expect: () => [
          const PinFileFieldsValidationError(
            id: invalidId,
            name: validName,
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.invalid,
            cancelled: false,
            networkError: false,
            isArFsEntityValid: true,
            isArFsEntityPublic: true,
            doesDataTransactionExist: true,
          ),
        ],
      );

      blocTest<PinFileBloc, PinFileState>(
        'network check won\'t run when id doesn\'t change while fields are '
        'valid',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        seed: () => PinFileFieldsValid(
          id: validFileId_1,
          name: validName,
          nameValidation: NameValidationResult.valid,
          idValidation: IdValidationResult.validEntityId,
          privacy: DrivePrivacy.public,
          dataContentType: 'application/json',
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          pinnedDataOwnerAddress: stubOwner,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: 'otro nombre', id: validFileId_1),
          )
          ..add(
            const FieldsChanged(name: 'pew! pew! pew!', id: validFileId_1),
          ),
        expect: () => [
          PinFileFieldsValid(
            id: validFileId_1,
            name: 'otro nombre',
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.validEntityId,
            privacy: DrivePrivacy.public,
            dataContentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
            pinnedDataOwnerAddress: stubOwner,
          ),
          PinFileFieldsValid(
            id: validFileId_1,
            name: 'pew! pew! pew!',
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.validEntityId,
            privacy: DrivePrivacy.public,
            dataContentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
            pinnedDataOwnerAddress: stubOwner,
          ),
        ],
      );

      blocTest<PinFileBloc, PinFileState>(
        'network check won\'t run when id doesn\'t change while network check '
        'is running',
        build: () => PinFileBloc(
          fileIdResolver: fileIdResolver,
          arweave: arweave,
          turboUploadService: turboService,
          profileCubit: profileCubit,
          driveDao: driveDao,
          driveID: stubDriveId,
          parentFolderId: stubFolderId,
        ),
        seed: () => const PinFileNetworkCheckRunning(
          id: validFileId_1,
          name: validName,
          nameValidation: NameValidationResult.valid,
          idValidation: IdValidationResult.validEntityId,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: 'otro nombre', id: validFileId_1),
          )
          ..add(
            const FieldsChanged(name: 'pew! pew! pew!', id: validFileId_1),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: 'otro nombre',
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.validEntityId,
          ),
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: 'pew! pew! pew!',
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.validEntityId,
          ),
        ],
      );
    });
  });
}
