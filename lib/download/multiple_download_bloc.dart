import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/utils/file_zipper.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'multiple_download_event.dart';
part 'multiple_download_state.dart';

class MultipleDownloadBloc
    extends Bloc<MultipleDownloadEvent, MultipleDownloadState> {
  final DownloadService _downloadService;

  MultipleDownloadBloc({
    required DownloadService downloadService,
  })  : _downloadService = downloadService,
        super(MultipleDownloadInitial()) {
    on<MultipleDownloadEvent>((event, emit) async {
      if (event is StartDownload) {
        await _downloadMultipleFiles(event.items, emit);
      }
    });
  }

  Future<void> _downloadMultipleFiles(
      List<ARFSFileEntity> items, Emitter<MultipleDownloadState> emit) async {
    try {
      final files = items.whereType<ARFSFileEntity>().toList();
      final ioFiles = <IOFile>[];

      final totalSize = files.map((e) => e.size).reduce((a, b) => a + b);

      if (_isSizeAbovePublicLimit(totalSize)) {
        emit(
          const MultipleDownloadFailure(
            FileDownloadFailureReason.fileAboveLimit,
          ),
        );

        return;
      }

      emit(
        MultipleDownloadInProgress(
          fileName: 'Multiple Files',
          totalByteCount: totalSize,
        ),
      );

      for (final file in files) {
        final dataBytes = await _downloadService.download(file.txId);

        final ioFile = await IOFile.fromData(
          dataBytes,
          name: file.name,
          lastModifiedDate: file.lastModifiedDate,
        );

        ioFiles.add(ioFile);
      }

      emit(const MultipleDownloadZippingFiles());

      await Future.delayed(const Duration(milliseconds: 200));

      await FileZipper(files: ioFiles).downloadZipFile();

      emit(const MultipleDownloadFinishedWithSuccess(title: 'Multiple Files'));
    } catch (e) {
      emit(const MultipleDownloadFailure(
        FileDownloadFailureReason.unknownError,
      ));
    }
  }

  bool _isSizeAbovePublicLimit(int size) {
    return size > publicDownloadSizeLimit;
  }
}
