import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drive_detail_state.dart';

class DriveDetailCubit extends Cubit<DriveDetailState> {
  final String driveId;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final AppConfig _config;

  StreamSubscription _folderSubscription;

  DriveDetailCubit({
    @required this.driveId,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
    @required AppConfig config,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _config = config,
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
      _driveDao.watchDriveById(driveId),
      _driveDao.watchFolderContentsAtPath(driveId, path),
      _profileCubit.startWith(null),
      (drive, folderContents, _) {
        if (folderContents?.folder != null) {
          final state = this.state is! DriveDetailLoadSuccess
              ? DriveDetailLoadSuccess()
              : this.state as DriveDetailLoadSuccess;
          final profile = _profileCubit.state;

          emit(
            state.copyWith(
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
    final file = await _driveDao.getFileById(driveId, state.selectedItemId);
    return '${_config.defaultArweaveGatewayUrl}/${file.dataTxId}';
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    return super.close();
  }
}
