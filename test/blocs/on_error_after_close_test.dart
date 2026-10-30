import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockMetadataWriteCostReader extends Mock
    implements MetadataWriteCostReader {}

/// An error reported to a cubit after it was closed - a late future, a
/// stream that outlived the dialog - reached an `onError` that emitted a
/// failure state. Emitting (or adding an event) after close throws, the
/// throw is reported to `onError` again, and it recursed until the stack
/// overflowed. Each `onError` that changes state now checks `isClosed`.
void main() {
  const driveId = 'drive-id';

  final closedCubits = <String, Future<BlocBase<Object?>> Function()>{
    'FsEntryInfoCubit': () async => FsEntryInfoCubit(
          driveId: driveId,
          driveDao: MockDriveDao(),
          licenseService: MockLicenseService(),
          arweave: MockArweaveService(),
        ),
    'FsEntryActivityCubit': () async => FsEntryActivityCubit(
          driveId: driveId,
          driveDao: MockDriveDao(),
          arweave: MockArweaveService(),
          profileCubit: MockProfileCubit(),
        ),
    'FolderCreateCubit': () async => FolderCreateCubit(
          driveId: driveId,
          parentFolderId: 'parent-id',
          profileCubit: MockProfileCubit(),
          arweave: MockArweaveService(),
          turboUploadService: MockTurboUploadService(),
          driveDao: MockDriveDao(),
        ),
    'FsEntryRenameCubit': () async => FsEntryRenameCubit(
          driveId: driveId,
          fileId: 'file-id',
          arweave: MockArweaveService(),
          turboUploadService: MockTurboUploadService(),
          driveDao: MockDriveDao(),
          profileCubit: MockProfileCubit(),
          crypto: MockArDriveCrypto(),
        ),
    'HideBloc': () async => HideBloc(
          arweaveService: MockArweaveService(),
          crypto: MockArDriveCrypto(),
          turboUploadService: MockTurboUploadService(),
          driveDao: MockDriveDao(),
          profileCubit: MockProfileCubit(),
          costReader: _MockMetadataWriteCostReader(),
        ),
  };

  for (final MapEntry(key: name, value: create) in closedCubits.entries) {
    test('$name takes an error after it is closed without recursing', () async {
      final cubit = await create();
      await cubit.close();

      expect(
        // ignore: invalid_use_of_protected_member
        () => cubit.onError(Exception('late'), StackTrace.current),
        returnsNormally,
      );
    });
  }
}
