import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/entities/entity.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HideBloc extends Bloc<HideEvent, HideState> {
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final ArDriveUploadPreparationManager _uploadPreparationManager;

  HideBloc({
    required ArweaveService arweaveService,
    required ArDriveCrypto crypto,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required ArDriveAuth auth,
    required ArDriveUploadPreparationManager uploadPreparationManager,
  })  : _arweave = arweaveService,
        _crypto = crypto,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _uploadPreparationManager = uploadPreparationManager,
        super(const InitialHideState()) {
    on<HideFileEvent>(_onHideFileEvent);
    on<HideFolderEvent>(_onHideFolderEvent);
    on<UnhideFileEvent>(_onUnhideFileEvent);
    on<UnhideFolderEvent>(_onUnhideFolderEvent);
    on<ConfirmUploadEvent>(_onConfirmUploadEvent);
    on<HideDriveEvent>(_onHideDriveEvent);
    on<UnhideDriveEvent>(_onUnhideDriveEvent);
    on<ErrorEvent>(_onErrorEvent);
    on<HideMultipleFilesEvent>(_onHideMultipleFilesEvent);
    on<UnhideMultipleFilesEvent>(_onUnHideMultipleFilesEvent);
  }

  bool _useTurboUpload = false;

  Future<void> _onHideMultipleFilesEvent(
    HideMultipleFilesEvent event,
    Emitter<HideState> emit,
  ) async {
    await _multipleHideOrUnhideFiles(event.fileIds, true, emit);
  }

  Future<void> _multipleHideOrUnhideFiles(
    List<String> fileIds,
    bool isHidden,
    Emitter<HideState> emit,
  ) async {
    final List<FileEntry> hiddenFileEntries = [];

    emit(HidingMultipleFilesState(
      hideAction: isHidden ? HideAction.hideFile : HideAction.unhideFile,
      fileEntries: const [],
      hiddenFileEntries: hiddenFileEntries,
      currentFile: null,
    ));

    final List<FileEntry> fileEntries = [];

    for (final fileId in fileIds) {
      final FileEntry currentFile = await _driveDao
          .fileById(
            fileId: fileId,
          )
          .getSingle();
      fileEntries.add(currentFile);
    }

    for (final fileEntry in fileEntries) {
      final hideEntitySettings = await _getFileHideEntitySettings(
        isHidden,
        fileEntry,
      );

      emit(HidingMultipleFilesState(
        hideAction: isHidden ? HideAction.hideFile : HideAction.unhideFile,
        fileEntries: fileEntries,
        currentFile: fileEntry,
        hiddenFileEntries: hiddenFileEntries,
      ));

      final dataItems = [hideEntitySettings.dataItem];

      final paymentInfo =
          await _uploadPreparationManager.getUploadPaymentInfoForEntityUpload(
              dataItem: hideEntitySettings.dataItem);

      _useTurboUpload = paymentInfo.isFreeUploadPossibleUsingTurbo;

      try {
        final profile = _profileCubit.state as ProfileLoggedIn;

        await _driveDao.transaction(() async {
          final dataBundle = await DataBundle.fromDataItems(
            items: dataItems,
          );

          if (_useTurboUpload) {
            final hideTx = await _arweave.prepareBundledDataItem(
              dataBundle,
              profile.user.wallet,
            );
            await _turboUploadService.postDataItem(
              dataItem: hideTx,
              wallet: profile.user.wallet,
            );
          } else {
            final hideTx = await _arweave.prepareDataBundleTx(
              dataBundle,
              profile.user.wallet,
            );
            await _arweave.postTx(hideTx);
          }

          await _saveNewRevision(hideEntitySettings);

          hiddenFileEntries.add(hideEntitySettings.entry);
          emit(HidingMultipleFilesState(
            hideAction: isHidden ? HideAction.hideFile : HideAction.unhideFile,
            fileEntries: fileEntries,
            hiddenFileEntries: hiddenFileEntries,
            currentFile: fileEntry,
          ));
        });
      } catch (e) {
        logger.e('Error while hiding', e);
        emit(FailureHideState(hideAction: state.hideAction));
      }
    }
    emit(SuccessHideState(hideAction: state.hideAction));
  }

  Future<void> _onUnHideMultipleFilesEvent(
    UnhideMultipleFilesEvent event,
    Emitter<HideState> emit,
  ) async {
    for (final fileId in event.fileIds) {
      final FileEntry currentFile = await _driveDao
          .fileById(
            fileId: fileId,
          )
          .getSingle();

      await _setHideStatus(
        currentFile,
        emit,
        isHidden: false,
      );
    }
  }

  Future<void> _onHideFileEvent(
    HideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.hideFile));

    final FileEntry currentFile =
        await _driveDao.fileById(fileId: event.fileId).getSingle();

    await _setHideStatus(
      currentFile,
      emit,
      isHidden: true,
    );
  }

  Future<void> _onHideFolderEvent(
    HideFolderEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.hideFolder));

    logger.d('Hiding folder ${event.folderId} in drive ${event.driveId}');

    final FolderEntry currentFolder =
        await _driveDao.folderById(folderId: event.folderId).getSingle();

    await _setHideStatus(
      currentFolder,
      emit,
      isHidden: true,
    );
  }

  Future<void> _onUnhideFileEvent(
    UnhideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.unhideFile));

    final FileEntry currentFile =
        await _driveDao.fileById(fileId: event.fileId).getSingle();

    await _setHideStatus(
      currentFile,
      emit,
      isHidden: false,
    );
  }

  Future<void> _onUnhideFolderEvent(
    UnhideFolderEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(
      hideAction: HideAction.unhideFolder,
    ));

    logger.d('Unhiding folder ${event.folderId} in drive ${event.driveId}');

    final FolderEntry currentFolder =
        await _driveDao.folderById(folderId: event.folderId).getSingle();

    await _setHideStatus(
      currentFolder,
      emit,
      isHidden: false,
    );
  }

  Future<void> _setHideStatus(
    Insertable currentEntry,
    Emitter<HideState> emit, {
    required bool isHidden,
  }) async {
    final entryIsFile = currentEntry is FileEntry;
    final entryIsFolder = currentEntry is FolderEntry;
    final entryIsDrive = currentEntry is Drive;
    assert(
      entryIsFile || entryIsFolder || entryIsDrive,
      'Entity to hide must be either a File, Folder or Drive',
    );

    HideEntitySettings hideEntitySettings;

    if (currentEntry is Drive) {
      hideEntitySettings = await _getDriveHideEntitySettings(
        isHidden,
        currentEntry,
      );
    } else if (currentEntry is FileEntry) {
      hideEntitySettings = await _getFileHideEntitySettings(
        isHidden,
        currentEntry,
      );
    } else {
      hideEntitySettings = await _getFolderHideEntitySettings(
        isHidden,
        currentEntry as FolderEntry,
      );
    }

    final dataItems = [hideEntitySettings.dataItem];

    final paymentInfo =
        await _uploadPreparationManager.getUploadPaymentInfoForEntityUpload(
            dataItem: hideEntitySettings.dataItem);

    _useTurboUpload = paymentInfo.isFreeUploadPossibleUsingTurbo;

    HideAction action;

    if (entryIsFile) {
      action = isHidden ? HideAction.hideFile : HideAction.unhideFile;
    } else if (entryIsDrive) {
      action = isHidden ? HideAction.hideDrive : HideAction.unhideDrive;
    } else {
      action = isHidden ? HideAction.hideFolder : HideAction.unhideFolder;
    }

    emit(
      ConfirmingHideState(
        uploadMethod: UploadMethod.turbo,
        hideAction: action,
        dataItems: dataItems,
        hideEntitySettings: hideEntitySettings,
      ),
    );
  }

  Future<HideEntitySettings<FolderEntry>> _getFolderHideEntitySettings(
    bool isHidden,
    FolderEntry currentEntry,
  ) async {
    final timestamp = DateTime.now();

    final newFolderEntry = currentEntry.copyWith(
      isHidden: isHidden,
      lastUpdated: timestamp,
    );

    final profile = _profileCubit.state as ProfileLoggedIn;

    final driveKey = await _driveDao.getDriveKey(
        currentEntry.driveId, profile.user.cipherKey);
    DriveKey? entityKey;

    if (driveKey != null) {
      entityKey = driveKey;
    }

    final dataItem = await _arweave.prepareEntityDataItem(
      newFolderEntry.asEntity(),
      profile.user.wallet,
      key: entityKey?.key,
    );

    final newEntryEntity = newFolderEntry.asEntity();

    newEntryEntity.txId = dataItem.id;

    return HideEntitySettings<FolderEntry>(
      isHidden: isHidden,
      entry: newFolderEntry,
      entity: newEntryEntity,
      dataItem: dataItem,
    );
  }

  Future<HideEntitySettings<FileEntry>> _getFileHideEntitySettings(
    bool isHidden,
    FileEntry currentEntry,
  ) async {
    final timestamp = DateTime.now();

    final newFileEntry = currentEntry.copyWith(
      isHidden: isHidden,
      lastUpdated: timestamp,
    );

    final profile = _profileCubit.state as ProfileLoggedIn;

    final driveKey = await _driveDao.getDriveKey(
        currentEntry.driveId, profile.user.cipherKey);
    SecretKey? entityKey;

    if (driveKey != null) {
      entityKey = await _crypto.deriveFileKey(
        driveKey.key,
        currentEntry.id,
      );
    }

    final dataItem = await _arweave.prepareEntityDataItem(
      newFileEntry.asEntity(),
      profile.user.wallet,
      key: entityKey,
    );

    final newEntryEntity = newFileEntry.asEntity();

    newEntryEntity.txId = dataItem.id;

    return HideEntitySettings<FileEntry>(
      isHidden: isHidden,
      entry: newFileEntry,
      entity: newEntryEntity,
      dataItem: dataItem,
    );
  }

  Future<HideEntitySettings<Drive>> _getDriveHideEntitySettings(
    bool isHidden,
    Drive currentEntry,
  ) async {
    final timestamp = DateTime.now();

    final newDriveEntry = currentEntry.copyWith(
      isHidden: isHidden,
      lastUpdated: timestamp,
    );

    final newEntryEntity = newDriveEntry.asEntity();
    final profile = _profileCubit.state as ProfileLoggedIn;

    newEntryEntity.ownerAddress = profile.user.walletAddress;

    final driveKey =
        await _driveDao.getDriveKey(currentEntry.id, profile.user.cipherKey);
    final SecretKey? entityKey;

    if (driveKey != null) {
      entityKey = driveKey.key;
    } else {
      entityKey = null;
    }

    final dataItem = await _arweave.prepareEntityDataItem(
      newEntryEntity,
      profile.user.wallet,
      key: entityKey,
    );

    newEntryEntity.txId = dataItem.id;

    return HideEntitySettings<Drive>(
      isHidden: isHidden,
      entry: newDriveEntry,
      entity: newEntryEntity,
      dataItem: dataItem,
    );
  }

  Future<void> _onConfirmUploadEvent(
    ConfirmUploadEvent event,
    Emitter<HideState> emit,
  ) async {
    try {
      final state = this.state as ConfirmingHideState;
      final profile = _profileCubit.state as ProfileLoggedIn;
      final dataItems = state.dataItems;

      emit(UploadingHideState(hideAction: state.hideAction));

      await _driveDao.transaction(() async {
        final dataBundle = await DataBundle.fromDataItems(
          items: dataItems,
        );

        if (_useTurboUpload) {
          final hideTx = await _arweave.prepareBundledDataItem(
            dataBundle,
            profile.user.wallet,
          );
          await _turboUploadService.postDataItem(
            dataItem: hideTx,
            wallet: profile.user.wallet,
          );
        } else {
          final hideTx = await _arweave.prepareDataBundleTx(
            dataBundle,
            profile.user.wallet,
          );
          await _arweave.postTx(hideTx);
        }

        await _saveNewRevision(state.hideEntitySettings);

        emit(SuccessHideState(hideAction: state.hideAction));
      });
    } catch (e) {
      logger.e('Error while hiding', e);
      emit(FailureHideState(hideAction: state.hideAction));
    }
  }

  Future<void> _saveNewRevision(
    HideEntitySettings settings,
  ) async {
    await _driveDao.transaction(() async {
      if (settings.entry is FileEntry) {
        await _driveDao.writeToFile(settings.entry as FileEntry);

        await _driveDao.insertFileRevision(
            (settings.entity as FileEntity).toRevisionCompanion(
          performedAction:
              settings.isHidden ? RevisionAction.hide : RevisionAction.unhide,
        ));
      } else if (settings.entry is FolderEntry) {
        await _driveDao.writeToFolder(settings.entry as FolderEntry);

        await _driveDao.insertFolderRevision(
            (settings.entity as FolderEntity).toRevisionCompanion(
          performedAction:
              settings.isHidden ? RevisionAction.hide : RevisionAction.unhide,
        ));
      } else if (settings.entry is Drive) {
        await _driveDao.writeToDrive(settings.entry as Drive);

        final driveCompanion =
            (settings.entity as DriveEntity).toRevisionCompanion(
          performedAction:
              settings.isHidden ? RevisionAction.hide : RevisionAction.unhide,
        );

        await _driveDao.insertDriveRevision(driveCompanion);
      }
    });
  }

  Future<void> _onHideDriveEvent(
    HideDriveEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.hideDrive));

    final drive = await _driveDao.driveById(driveId: event.driveId).getSingle();

    await _setHideStatus(
      drive,
      emit,
      isHidden: true,
    );
  }

  Future<void> _onUnhideDriveEvent(
    UnhideDriveEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(
        const PreparingAndSigningHideState(hideAction: HideAction.unhideDrive));

    final drive = await _driveDao.driveById(driveId: event.driveId).getSingle();

    await _setHideStatus(
      drive,
      emit,
      isHidden: false,
    );
  }

  void _onErrorEvent(
    ErrorEvent event,
    Emitter<HideState> emit,
  ) {
    emit(FailureHideState(hideAction: event.hideAction));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    add(ErrorEvent(
      error: error,
      stackTrace: stackTrace,
      hideAction: state.hideAction,
    ));
    super.onError(error, stackTrace);
  }
}

class HideEntitySettings<T> {
  final bool isHidden;
  final T entry;
  final EntityWithCustomMetadata entity;
  final DataItem dataItem;

  HideEntitySettings({
    required this.isHidden,
    required this.entry,
    required this.entity,
    required this.dataItem,
  });
}
