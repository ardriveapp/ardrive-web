import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drive_detail_state.dart';

class DriveDetailCubit extends Cubit<DriveDetailState> {
  final String _driveId;
  final ProfileBloc _profileBloc;
  final UploadBloc _uploadBloc;
  final DriveDao _driveDao;

  StreamSubscription _folderSubscription;

  DriveDetailCubit({
    @required String driveId,
    @required ProfileBloc profileBloc,
    @required UploadBloc uploadBloc,
    @required DriveDao driveDao,
  })  : _driveId = driveId,
        _profileBloc = profileBloc,
        _uploadBloc = uploadBloc,
        _driveDao = driveDao,
        super(DriveDetailLoadInProgress()) {
    if (driveId != null) {
      openFolderAtPath('');
    }
  }

  void openFolderAtPath(String path) {
    emit(DriveDetailLoadInProgress());

    unawaited(_folderSubscription?.cancel());

    _folderSubscription =
        Rx.combineLatest3<Drive, FolderWithContents, ProfileState, void>(
      _driveDao.watchDriveById(_driveId),
      _driveDao.watchFolderContentsAtPath(_driveId, path),
      _profileBloc.startWith(null),
      (drive, folderContents, _) {
        if (folderContents?.folder != null) {
          final profile = _profileBloc.state;
          emit(
            DriveDetailLoadSuccess(
              currentDrive: drive,
              hasWritePermissions: profile is ProfileLoaded &&
                  drive.ownerAddress == profile.wallet.address,
              currentFolder: folderContents,
            ),
          );
        }
      },
    ).listen((_) {});
  }

  void selectItem(String itemId, {bool isFolder = false}) {
    final state = this.state as DriveDetailLoadSuccess;
    emit(state.copyWith(
      selectedItemId: itemId,
      selectedItemIsFolder: isFolder,
    ));
  }

  void toggleSelectedItemDetails() {
    final state = this.state as DriveDetailLoadSuccess;
    emit(state.copyWith(
        showSelectedItemDetails: !state.showSelectedItemDetails));
  }

  Future<String> getSelectedFilePreviewUrl() async {
    final state = this.state as DriveDetailLoadSuccess;
    final file = await _driveDao.getFileById(_driveId, state.selectedItemId);
    return 'https://arweave.dev/${file.dataTxId}';
  }

  void prepareFileUpload(FileEntity fileDetails, Uint8List fileData) async {
    final profile = _profileBloc.state as ProfileLoaded;
    final currentState = state as DriveDetailLoadSuccess;
    final currentFolder = currentState.currentFolder.folder;
    final drive = currentState.currentDrive;

    fileDetails
      ..driveId = _driveId
      ..parentFolderId = currentFolder.id;

    final driveKey = drive.isPrivate
        ? await _driveDao.getDriveKey(_driveId, profile.cipherKey)
        : null;

    _uploadBloc.add(
      PrepareFileUpload(
        fileDetails,
        '${currentFolder.path}/${fileDetails.name}',
        fileData,
        driveKey,
      ),
    );
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    return super.close();
  }
}
