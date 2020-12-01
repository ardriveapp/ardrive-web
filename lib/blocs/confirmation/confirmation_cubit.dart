import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';

part 'confirmation_state.dart';

const kRequiredTxConfirmationCount = 15;

/// The [ConfirmationCubit] periodically checks the status of unconfirmed transactions of folders and files
/// and updates them accordingly.
class ConfirmationCubit extends Cubit<ConfirmationState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;

  StreamSubscription _periodicSub;

  ConfirmationCubit(
      {@required ArweaveService arweave, @required DriveDao driveDao})
      : _arweave = arweave,
        _driveDao = driveDao,
        super(ConfirmationInitial()) {
    _periodicSub = interval(const Duration(minutes: 2))
        .startWith(null)
        .listen((_) => updateTransactionStatuses());
  }

  Future<void> updateTransactionStatuses() async {
    final unconfirmedFolderRevisions =
        await _driveDao.selectUnconfirmedFolderRevisions().get();
    final unconfirmedFileRevisions =
        await _driveDao.selectUnconfirmedFileRevisions().get();

    // Construct a list of transactions that are unconfirmed, filtering out ones that are already confirmed.
    final unconfirmedTxIds = unconfirmedFolderRevisions
        .map((r) => r.metadataTxId)
        .followedBy(unconfirmedFileRevisions
            .where((r) => r.metadataTxConfirmed)
            .map((r) => r.metadataTxId))
        .followedBy(unconfirmedFileRevisions
            .where((r) => r.dataTxConfirmed)
            .map((r) => r.dataTxId))
        .toList();

    final txConfirmations =
        await _arweave.getTransactionConfirmations(unconfirmedTxIds);

    await _driveDao.transaction(() async {
      for (final folderRevision in unconfirmedFolderRevisions) {
        final metadataTxConfirmed =
            txConfirmations[folderRevision.metadataTxId] >=
                kRequiredTxConfirmationCount;

        await _driveDao.writeToFolderRevision(
          FolderRevisionsCompanion(
            id: Value(folderRevision.id),
            metadataTxConfirmed: Value(metadataTxConfirmed),
          ),
        );
      }

      for (final fileRevision in unconfirmedFileRevisions) {
        // If a transaction does not have a corresponding confirmation count, it was filtered out above and
        // has already been confirmed.
        final metadataTxConfirmed =
            txConfirmations.containsKey(fileRevision.metadataTxId)
                ? txConfirmations[fileRevision.metadataTxId] >=
                    kRequiredTxConfirmationCount
                : true;

        final dataTxConfirmed =
            txConfirmations.containsKey(fileRevision.dataTxId)
                ? txConfirmations[fileRevision.dataTxId] >=
                    kRequiredTxConfirmationCount
                : true;

        await _driveDao.writeToFileRevision(
          FileRevisionsCompanion(
            id: Value(fileRevision.id),
            metadataTxConfirmed: Value(metadataTxConfirmed),
            dataTxConfirmed: Value(dataTxConfirmed),
          ),
        );
      }
    });
  }

  @override
  Future<void> close() {
    _periodicSub?.cancel();
    return super.close();
  }
}
