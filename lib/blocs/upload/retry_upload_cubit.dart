import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';

part 'retry_upload_state.dart';

class RetryUploadCubit extends Cubit<RetryUploadState> {
  final ArweaveService _arweave;

  final FileWithLatestRevisionTransactions _uploadedFile;

  RetryUploadCubit({
    @required ArweaveService arweave,
    FileWithLatestRevisionTransactions uploadedFile,
  })  : _arweave = arweave,
        _uploadedFile = uploadedFile,
        super(RetryUploadPreparationInProgress()) {
    () async {
      unawaited(startReUpload());
    }();
  }

  Future<void> startReUpload() async {
    emit(RetryUploadInProgress());

    try {
      if (_uploadedFile.dataTx != null) {
        final uploader = await _arweave.getUploader(_uploadedFile.dataTxId);
        while (uploader.uploadedChunks != uploader.totalChunks) {
          await uploader.uploadChunk();
        }
      }
      emit(RetryUploadComplete());
    } catch (e) {
      emit(RetryUploadFailure());
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(RetryUploadFailure());
    super.onError(error, stackTrace);

    print('Failed to upload file: $error $stackTrace');
  }
}
