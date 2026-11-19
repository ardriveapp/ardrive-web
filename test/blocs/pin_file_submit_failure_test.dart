import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _FailingDao extends Mock implements DriveDao {
  @override
  Future<T> transaction<T>(Future<T> Function() action,
          {bool requireNew = false}) async =>
      throw Exception('network');
}

class _MockResolver extends Mock implements FileIdResolver {}

class _MockTurbo extends Mock implements TurboUploadService {}

class _MockProfile extends MockCubit<ProfileState> implements ProfileCubit {}

/// A pin that could not be made leaves the dialog as it was: the bloc reports
/// the error and goes back to the valid fields, so the dialog stays open on
/// them and Try again submits them again.
void main() {
  final valid = PinFileFieldsValid(
    id: '01234567-89ab-cdef-0123-456789abcdef',
    name: 'notes',
    nameValidation: NameValidationResult.valid,
    idValidation: IdValidationResult.validEntityId,
    privacy: DrivePrivacy.public,
    dataContentType: 'text/plain',
    dateCreated: DateTime(2024),
    size: 1,
    dataTxId: 'HelloHelloHelloHelloHelloHelloHelloH-+_ABCD',
    pinnedDataOwnerAddress: '0000000000000000000000000000000000000000000',
  );

  blocTest<PinFileBloc, PinFileState>(
    'an upload error is reported, then the valid fields are back',
    build: () {
      final profile = _MockProfile();
      when(() => profile.state).thenReturn(
        ProfileLoggedIn(
          user: User(
            password: 'password',
            wallet: getTestWallet(),
            walletAddress: 'address',
            walletBalance: BigInt.one,
            cipherKey: SecretKey(List.filled(32, 7)),
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ),
      );
      final driveDao = _FailingDao();
      return PinFileBloc(
        fileIdResolver: _MockResolver(),
        arweave: MockArweaveService(),
        turboUploadService: _MockTurbo(),
        profileCubit: profile,
        driveDao: driveDao,
        driveID: 'drive',
        parentFolderId: 'folder',
        crypto: MockArDriveCrypto(),
      );
    },
    seed: () => valid,
    act: (bloc) => bloc.add(const PinFileSubmit()),
    expect: () => [
      isA<PinFileCreating>(),
      isA<PinFileError>(),
      isA<PinFileFieldsValid>(),
    ],
  );
}
