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
    String initialFolderId,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
    @required AppConfig config,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _config = config,
        super(DriveDetailLoadInProgress()) {
    if (driveId == null) {
      return;
    }

    if (initialFolderId != null) {
      // TODO: Handle deep-linking folders of unattached drives.
      Future.microtask(() async {
        final folder =
            await _driveDao.folderById(driveId, initialFolderId).getSingle();
        // Open the root folder if the deep-linked folder could not be found.
        openFolder(path: folder?.path ?? '');
      });
    } else {
      openFolder(path: '');
    }
  }

  void openFolder(
      {@required String path,
      DriveOrder contentOrderBy = DriveOrder.name,
      OrderingMode contentOrderingMode = OrderingMode.asc}) {
    emit(DriveDetailLoadInProgress());

    unawaited(_folderSubscription?.cancel());

    _folderSubscription =
        Rx.combineLatest3<Drive, FolderWithContents, ProfileState, void>(
      _driveDao.driveById(driveId).watchSingle(),
      _driveDao.watchFolderContents(driveId,
          folderPath: path,
          orderBy: contentOrderBy,
          orderingMode: contentOrderingMode),
      _profileCubit.startWith(null),
      (drive, folderContents, _) {
        if (drive == null) {
          emit(DriveDetailLoadNotFound());
          return;
        }

        if (folderContents?.folder == null) {
          // Emit the loading state as it can be a while between the drive being not found, then added,
          // and then the folders being loaded.
          emit(DriveDetailLoadInProgress());
        } else {
          final state = this.state is DriveDetailLoadSuccess
              ? this.state as DriveDetailLoadSuccess
              : DriveDetailLoadSuccess();
          final profile = _profileCubit.state;

          emit(
            state.copyWith(
              currentDrive: drive,
              hasWritePermissions: profile is ProfileLoggedIn &&
                  drive.ownerAddress == profile.wallet.address,
              currentFolder: folderContents,
              contentOrderBy: contentOrderBy,
              contentOrderingMode: contentOrderingMode,
            ),
          );
        }
      },
    ).listen((_) {});
  }

  Future<void> selectItem(String itemId, {bool isFolder = false}) async {
    var state = this.state as DriveDetailLoadSuccess;

    state = state.copyWith(
      selectedItemId: itemId,
      selectedItemIsFolder: isFolder,
    );

    if (state.currentDrive.isPublic && !isFolder) {
      final file =
          await _driveDao.fileById(driveId, state.selectedItemId).getSingle();
      state = state.copyWith(
          selectedFilePreviewUrl: Uri.parse(
              '${_config.defaultArweaveGatewayUrl}/${file.dataTxId}'));
    }

    emit(state);
  }

  void sortFolder(
      {DriveOrder contentOrderBy = DriveOrder.name,
      OrderingMode contentOrderingMode = OrderingMode.asc}) {
    final state = this.state as DriveDetailLoadSuccess;
    openFolder(
        path: state.currentFolder.folder.path,
        contentOrderBy: contentOrderBy,
        contentOrderingMode: contentOrderingMode);
  }

  void toggleSelectedItemDetails() {
    final state = this.state as DriveDetailLoadSuccess;
    emit(state.copyWith(
        showSelectedItemDetails: !state.showSelectedItemDetails));
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    return super.close();
  }
}
