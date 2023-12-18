import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HideBloc extends Bloc<HideEvent, HideState> {
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  HideBloc({
    required ArweaveService arweaveService,
    required ArDriveCrypto crypto,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
  })  : _arweave = arweaveService,
        _crypto = crypto,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(const InitialHideState()) {
    on<HideFileEvent>(_onHideFileEvent);
  }

  Future<void> _onHideFileEvent(
    HideFileEvent event,
    Emitter<HideState> emit,
  ) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    late DataItem fileDataItem;

    await _driveDao.transaction(() async {
      final FileEntry currentFile = await _driveDao
          .fileById(
            driveId: event.driveId,
            fileId: event.fileId,
          )
          .getSingle();
      final newFile = currentFile.copyWith(
        isHidden: true,
        lastUpdated: DateTime.now(),
      );
      final fileEntity = newFile.asEntity();

      final driveKey = await _driveDao.getDriveKey(
        event.driveId,
        profile.cipherKey,
      );
      final fileKey = driveKey != null
          ? await _crypto.deriveFileKey(driveKey, currentFile.id)
          : null;
      fileDataItem = await _arweave.prepareEntityDataItem(
        fileEntity,
        profile.wallet,
        key: fileKey,
      );

      await _driveDao.writeToFile(newFile);
      fileEntity.txId = fileDataItem.id;

      // TODO: revision activity
      // await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
      //   performedAction: RevisionAction.move,
      // ));
    });

    if (_turboUploadService.useTurboUpload) {
      await _turboUploadService.postDataItem(
        dataItem: fileDataItem,
        wallet: profile.wallet,
      );
    } else {
      final hideTx = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(items: [fileDataItem]),
        profile.wallet,
      );
      await _arweave.postTx(hideTx);
    }
  }
}
