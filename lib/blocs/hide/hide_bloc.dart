import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/entities/entity.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HideBloc extends Bloc<HideEvent, HideState> {
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final MetadataWriteCostReader _costReader;

  HideBloc({
    required ArweaveService arweaveService,
    required ArDriveCrypto crypto,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required MetadataWriteCostReader costReader,
  })  : _arweave = arweaveService,
        _crypto = crypto,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _costReader = costReader,
        super(const InitialHideState()) {
    on<HideFileEvent>(_onHideFileEvent);
    on<HideFolderEvent>(_onHideFolderEvent);
    on<UnhideFileEvent>(_onUnhideFileEvent);
    on<UnhideFolderEvent>(_onUnhideFolderEvent);
    // A second Confirm while one is under way is dropped, not queued.
    on<ConfirmUploadEvent>(_onConfirmUploadEvent, transformer: droppable());
    on<HideCostRefreshEvent>(_onCostRefreshEvent);
    on<HideDriveEvent>(_onHideDriveEvent);
    on<UnhideDriveEvent>(_onUnhideDriveEvent);
    on<ErrorEvent>(_onErrorEvent);
  }

  /// A write is under way.
  var _writing = false;

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

    HideAction action;

    if (entryIsFile) {
      action = isHidden ? HideAction.hideFile : HideAction.unhideFile;
    } else if (entryIsDrive) {
      action = isHidden ? HideAction.hideDrive : HideAction.unhideDrive;
    } else {
      action = isHidden ? HideAction.hideFolder : HideAction.unhideFolder;
    }

    final confirming = ConfirmingHideState(
      uploadMethod:
          _costReader.usesTurbo ? UploadMethod.turbo : UploadMethod.ar,
      hideAction: action,
      dataItems: dataItems,
      hideEntitySettings: hideEntitySettings,
    );
    emit(await _withCost(confirming));
  }

  /// [state] with the cost of its write read: Turbo's free upload allowance,
  /// or its price in Turbo Credits, the way a license is priced. The wallet
  /// pays only when Turbo uploads are off.
  Future<ConfirmingHideState> _withCost(ConfirmingHideState state) async {
    MetadataWriteCost cost;
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      cost = await _costReader.read(
        itemSizes: [
          for (final item in state.dataItems) signedDataItemSize(item),
        ],
        wallet: profile.user.wallet,
        walletBalance: profile.user.walletBalance,
        refusedByTurbo: state.refused,
      );
    } catch (e) {
      logger.e('Could not price the hide', e);
      cost = MetadataWriteCost(MetadataWriteCostReader.unavailable());
    }
    return ConfirmingHideState(
      uploadMethod: state.uploadMethod,
      hideAction: state.hideAction,
      dataItems: state.dataItems,
      hideEntitySettings: state.hideEntitySettings,
      cost: cost,
      refused: state.refused,
    );
  }

  Future<void> _onCostRefreshEvent(
    HideCostRefreshEvent event,
    Emitter<HideState> emit,
  ) async {
    final state = this.state;
    if (_writing || state is! ConfirmingHideState) return;
    final reading = ConfirmingHideState(
      uploadMethod: state.uploadMethod,
      hideAction: state.hideAction,
      dataItems: state.dataItems,
      hideEntitySettings: state.hideEntitySettings,
      refused: state.refused,
    );
    emit(reading);
    emit(await _withCost(reading));
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
    final state = this.state;
    // Only what is free, or paid for the way the review showed: never with
    // no price, or credits short, and never twice.
    if (_writing || state is! ConfirmingHideState) return;
    final cost = state.cost;
    if (cost == null || !cost.summary.isCovered) return;
    _writing = true;

    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final dataItems = state.dataItems;

      emit(UploadingHideState(hideAction: state.hideAction));

      if (_turboUploadService.useTurboUpload) {
        // Through Turbo, like every other change: free under the allowance,
        // Turbo Credits after it. Never the wallet as a fallback.
        for (final item in dataItems) {
          await _turboUploadService.postDataItem(
            dataItem: item,
            wallet: profile.user.wallet,
            headers: cost.headers,
          );
        }
      } else {
        final hideTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(items: dataItems),
          profile.user.wallet,
        );
        await _arweave.postTx(hideTx);
      }

      await _saveNewRevision(state.hideEntitySettings);
      _writing = false;
      emit(SuccessHideState(hideAction: state.hideAction));
    } catch (e) {
      _writing = false;
      logger.e('Error while hiding', e);
      if (isTurboPaymentError(e)) {
        // Not paid for after all: the review, with the balance read again
        // and Add credits.
        final refused = ConfirmingHideState(
          uploadMethod: state.uploadMethod,
          hideAction: state.hideAction,
          dataItems: state.dataItems,
          hideEntitySettings: state.hideEntitySettings,
          refused: true,
        );
        emit(refused);
        emit(await _withCost(refused));
        return;
      }
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
