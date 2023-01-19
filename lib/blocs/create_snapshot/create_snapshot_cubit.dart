// is it ok to have dart:io here?
import 'dart:io';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/snapshot_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'create_snapshot_state.dart';

class CreateSnapshotCubit extends Cubit<CreateSnapshotState> {
  // FIXME: this is a skeleton, yet missing to add the functionality

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final String _tempFilePath;
  final ProfileCubit _profileCubit;

  late DriveID driveId;
  late Range range;
  late int currentHeight;

  CreateSnapshotCubit({
    required String tempFile,
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
  })  : _tempFilePath = tempFile,
        _arweave = arweave,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(CreateSnapshotInitial());

  Future<void> selectDriveAndHeightRange(
    DriveID driveId,
    Range range,
    int currentHeight,
  ) async {
    this.driveId = driveId;
    this.range = range;
    this.currentHeight = currentHeight;

    // TODO: validate drive id and range
    if (_isValidHeightRange()) {
      // TODO -
    }

    // declares the writing stream to the temporal file
    final tempFile = File(_tempFilePath);
    final tempFileSink = tempFile.openWrite();

    emit(ComputingSnapshotData(
      driveId: driveId,
      range: range,
    ));

    // declare the GQL read stream out of arweave
    final gqlEdgesStream = _arweave.getSegmentedTransactionsFromDrive(
      driveId,
      minBlockHeight: range.start,
      maxBlockHeight: range.end,
    );

    // transforms the stream of arrays into a flat stream
    final flatGQLEdgesStream = gqlEdgesStream.expand((element) => element);

    // maps the items to GQL Nodes
    final gqlNodesStream = flatGQLEdgesStream.map((edge) => edge.node);

    // declares the reading stream from the SnapshotItemToBeCreated
    final snapshotItemToBeCreated = SnapshotItemToBeCreated(
      blockStart: range.start,
      blockEnd: range.end,
      driveId: driveId,
      subRanges: HeightRange(rangeSegments: [range]),
      source: gqlNodesStream,
      jsonMetadataOfTxId: _jsonMetadataOfTxId,
    );

    // Stream snapshot data to the temporal file
    await for (final item in snapshotItemToBeCreated.getSnapshotData()) {
      tempFileSink.add(item);
    }

    final dataStart = snapshotItemToBeCreated.dataStart;
    final dataEnd = snapshotItemToBeCreated.dataEnd;

    // close the file as writing, and open as reading
    await tempFileSink.close();
    final tempFileRead = tempFile.openRead();

    // declares the new snapshot entity
    final snapshotEntity = SnapshotEntity(
      id: const Uuid().v4(), // TODO: take from arguments (?)
      driveId: driveId,
      blockStart: range.start,
      blockEnd: range.end,
      dataStart: dataStart,
      dataEnd: dataEnd,
      data: Uint8List.fromList(
        await tempFileRead.expand((element) => element).toList(),
      ),
    );

    final profile = _profileCubit.state as ProfileLoggedIn;
    final wallet = profile.wallet;
    final preparedTx = await _arweave.prepareEntityTx(
      snapshotEntity,
      wallet,
      // key is null because we don't re-encrypt the snapshot data
    );

    snapshotEntity.txId = preparedTx.id;

    final uploadSnapshotItemParams = CreateSnapshotParameters(
      signedTx: preparedTx,
      addSnapshotItemToDatabase: () => _driveDao.transaction(() async {
        await _driveDao.writeSnapshotEntity(snapshotEntity);
      }),
    );

    // TODO: estimate upload cost
    const arUploadCost = '0';
    const usdUploadCost = 0.0;

    // TODO: emit ConfirmUpload or ComputeSnapshotDataFailure
    emit(ConfirmSnapshotCreation(
      snapshotSize: tempFile.lengthSync(),
      arUploadCost: arUploadCost,
      usdUploadCost: usdUploadCost,
      createSnapshotParams: uploadSnapshotItemParams,
    ));
  }

  bool _isValidHeightRange() {
    return range.end <= currentHeight;
  }

  Future<String> _jsonMetadataOfTxId(String txId) async {
    // TODO: implement me
    // Will try to read from the DB, and from netwirk if the data is not present
    return '';
  }

  void confirmSnapshotCreation() async {
    // if (await _profileCubit.logoutIfWalletMismatch()) {
    //   emit(CreateManifestWalletMismatch());
    //   return;
    // }

    try {
      final params = (state as ConfirmSnapshotCreation).createSnapshotParams;

      emit(UploadingSnapshot());

      await _arweave.client.transactions.post(params.signedTx);
      await params.addSnapshotItemToDatabase();

      emit(SnapshotUploadSuccess());
    } catch (err) {
      // ignore: avoid_print
      print('Error while posting the snapshot transaction: $err');
      addError(err);
    }
  }
}

class CreateSnapshotParameters {
  final Transaction signedTx;
  final Future<void> Function() addSnapshotItemToDatabase;

  CreateSnapshotParameters({
    required this.signedTx,
    required this.addSnapshotItemToDatabase,
  });
}
