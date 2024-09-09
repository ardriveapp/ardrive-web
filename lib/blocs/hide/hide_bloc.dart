import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/uploader.dart';
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
    on<ErrorEvent>(_onErrorEvent);
  }

  bool _useTurboUpload = false;

  Future<void> _onHideFileEvent(
    HideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    emit(const PreparingAndSigningHideState(hideAction: HideAction.hideFile));

    final FileEntry currentFile = await _driveDao
        .fileById(
          driveId: event.driveId,
          fileId: event.fileId,
        )
        .getSingle();

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

    final FolderEntry currentFolder = await _driveDao
        .folderById(
          driveId: event.driveId,
          folderId: event.folderId,
        )
        .getSingle();

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

    final FileEntry currentFile = await _driveDao
        .fileById(
          driveId: event.driveId,
          fileId: event.fileId,
        )
        .getSingle();

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

    final FolderEntry currentFolder = await _driveDao
        .folderById(
          driveId: event.driveId,
          folderId: event.folderId,
        )
        .getSingle();

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

    assert(
      entryIsFile || entryIsFolder,
      'Entity to hide must be either a File or a Folder',
    );

    final entity = entryIsFile
        ? currentEntry.asEntity()
        : (currentEntry as FolderEntry).asEntity();

    final driveId = entryIsFile
        ? currentEntry.driveId
        : (currentEntry as FolderEntry).driveId;

    final profile = _profileCubit.state as ProfileLoggedIn;
    final driveKey =
        await _driveDao.getDriveKey(driveId, profile.user.cipherKey);
    final SecretKey? entityKey;

    if (driveKey != null) {
      if (entryIsFile) {
        entityKey = await _crypto.deriveFileKey(
          driveKey,
          (entity as FileEntity).id!,
        );
      } else {
        entityKey = driveKey;
      }
    } else {
      entityKey = null;
    }

    final newEntry = entryIsFile
        ? currentEntry.copyWith(
            isHidden: isHidden,
            lastUpdated: DateTime.now(),
          )
        : (currentEntry as FolderEntry).copyWith(
            isHidden: isHidden,
            lastUpdated: DateTime.now(),
          );
    final newEntryEntity = entryIsFile
        ? (newEntry as FileEntry).asEntity()
        : (newEntry as FolderEntry).asEntity();

    final dataItem = await _arweave.prepareEntityDataItem(
      newEntryEntity,
      profile.user.wallet,
      key: entityKey,
    );

    final dataItems = [dataItem];

    final paymentInfo = await _uploadPreparationManager
        .getUploadPaymentInfoForEntityUpload(dataItem: dataItem);

    _useTurboUpload = paymentInfo.isFreeUploadPossibleUsingTurbo;

    Future<void> saveEntitiesToDb() async {
      await _driveDao.transaction(() async {
        if (entryIsFile) {
          await _driveDao.writeToFile(newEntry as FileEntry);
        } else {
          await _driveDao.writeToFolder(newEntry as FolderEntry);
        }

        newEntryEntity.txId = dataItem.id;

        if (entryIsFile) {
          await _driveDao.insertFileRevision(
              (newEntryEntity as FileEntity).toRevisionCompanion(
            performedAction:
                isHidden ? RevisionAction.hide : RevisionAction.unhide,
          ));
        } else {
          await _driveDao.insertFolderRevision(
              (newEntryEntity as FolderEntity).toRevisionCompanion(
            performedAction:
                isHidden ? RevisionAction.hide : RevisionAction.unhide,
          ));
        }
      });
    }

    final hideAction = entryIsFile
        ? (isHidden ? HideAction.hideFile : HideAction.unhideFile)
        : (isHidden ? HideAction.hideFolder : HideAction.unhideFolder);

    emit(
      ConfirmingHideState(
        uploadMethod: UploadMethod.turbo,
        hideAction: hideAction,
        dataItems: dataItems,
        saveEntitiesToDb: saveEntitiesToDb,
      ),
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

        await state.saveEntitiesToDb();

        emit(SuccessHideState(hideAction: state.hideAction));
      });
    } catch (e) {
      logger.e('Error while hiding', e);
      emit(FailureHideState(hideAction: state.hideAction));
    }
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
