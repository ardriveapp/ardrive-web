import 'dart:async';

import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drive_detail_state.dart';

class DriveDetailCubit extends Cubit<DriveDetailState> {
  final String driveId;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final AppConfig _config;

  StreamSubscription? _folderSubscription;
  final _defaultAvailableRowsPerPage = [25, 50, 75, 100];

  DriveDetailCubit({
    required this.driveId,
    String? initialFolderId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required AppConfig config,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _config = config,
        super(DriveDetailLoadInProgress()) {
    if (driveId.isEmpty) {
      return;
    }

    if (initialFolderId != null) {
      // TODO: Handle deep-linking folders of unattached drives.
      Future.microtask(() async {
        final folder = await _driveDao
            .folderById(driveId: driveId, folderId: initialFolderId)
            .getSingleOrNull();
        // Open the root folder if the deep-linked folder could not be found.

        openFolder(path: folder?.path ?? rootPath);
        // The empty string here is required to open the root folder
      });
    } else {
      openFolder(path: rootPath);
    }
  }

  void openFolder({
    required String path,
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) async {
    emit(DriveDetailLoadInProgress());

    await _folderSubscription?.cancel();
    // For attaching drives. If drive is not found, emit state to prompt drive attach
    final drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();
    if (drive == null) {
      emit(DriveDetailLoadNotFound());
      return;
    }
    _folderSubscription =
        Rx.combineLatest3<Drive, FolderWithContents, ProfileState, void>(
      _driveDao.driveById(driveId: driveId).watchSingle(),
      _driveDao.watchFolderContents(
        driveId,
        folderPath: path,
        orderBy: contentOrderBy,
        orderingMode: contentOrderingMode,
      ),
      _profileCubit.stream.startWith(ProfileCheckingAvailability()),
      (drive, folderContents, _) async {
        final state = this.state is DriveDetailLoadSuccess
            ? this.state as DriveDetailLoadSuccess
            : null;
        final profile = _profileCubit.state;

        // Set selected item to subfolder if the folder being viewed is not drive root

        final maybeSelectedItem = folderContents.folder.id != drive.rootFolderId
            ? SelectedFolder(folder: folderContents.folder)
            : null;
        var availableRowsPerPage = _defaultAvailableRowsPerPage;

        availableRowsPerPage = calculateRowsPerPage(
          folderContents.files.length + folderContents.subfolders.length,
        );

        if (state != null) {
          emit(state.copyWith(
            currentDrive: drive,
            hasWritePermissions: profile is ProfileLoggedIn &&
                drive.ownerAddress == profile.walletAddress,
            folderInView: folderContents,
            contentOrderBy: contentOrderBy,
            contentOrderingMode: contentOrderingMode,
            rowsPerPage: availableRowsPerPage.first,
            availableRowsPerPage: availableRowsPerPage,
            maybeSelectedItem: maybeSelectedItem,
          ));
        } else {
          emit(DriveDetailLoadSuccess(
            currentDrive: drive,
            hasWritePermissions: profile is ProfileLoggedIn &&
                drive.ownerAddress == profile.walletAddress,
            folderInView: folderContents,
            contentOrderBy: contentOrderBy,
            contentOrderingMode: contentOrderingMode,
            rowsPerPage: availableRowsPerPage.first,
            availableRowsPerPage: availableRowsPerPage,
            maybeSelectedItem: maybeSelectedItem,
          ));
        }
      },
    ).listen((_) {});
  }

  List<int> calculateRowsPerPage(int totalEntries) {
    List<int> availableRowsPerPage;
    if (totalEntries < _defaultAvailableRowsPerPage.first) {
      availableRowsPerPage = <int>[totalEntries];
    } else {
      availableRowsPerPage = _defaultAvailableRowsPerPage;
    }
    return availableRowsPerPage;
  }

  void setRowsPerPage(int rowsPerPage) {
    switch (state.runtimeType) {
      case DriveDetailLoadSuccess:
        emit(
          (state as DriveDetailLoadSuccess).copyWith(
            rowsPerPage: rowsPerPage,
          ),
        );
    }
  }

  Future<void> selectItem(SelectedItem selectedItem) async {
    var state = this.state as DriveDetailLoadSuccess;

    state = state.copyWith(maybeSelectedItem: selectedItem);
    if (state.currentDrive.isPublic && selectedItem is SelectedFile) {
      final fileWithRevisions = _driveDao.latestFileRevisionByFileId(
        driveId: driveId,
        fileId: selectedItem.id,
      );
      final dataTxId = (await fileWithRevisions.getSingle()).dataTxId;
      state = state.copyWith(
          selectedFilePreviewUrl:
              Uri.parse('${_config.defaultArweaveGatewayUrl}/$dataTxId'));
    }

    emit(state);
  }

  void sortFolder(
      {DriveOrder contentOrderBy = DriveOrder.name,
      OrderingMode contentOrderingMode = OrderingMode.asc}) {
    final state = this.state as DriveDetailLoadSuccess;
    openFolder(
      path: state.folderInView.folder.path,
      contentOrderBy: contentOrderBy,
      contentOrderingMode: contentOrderingMode,
    );
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
