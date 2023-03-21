import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/utils/data_size.dart';
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

      final ioFilesDownloaded =
          await downloadFilesInChunks(files, _downloadService);

      emit(const MultipleDownloadZippingFiles());

      await Future.delayed(const Duration(milliseconds: 200));

      await FileZipper(files: ioFilesDownloaded).downloadZipFile();

      emit(const MultipleDownloadFinishedWithSuccess(title: 'Multiple Files'));
    } catch (e) {
      emit(const MultipleDownloadFailure(
        FileDownloadFailureReason.unknownError,
      ));
    }
  }

  Future<List<IOFile>> downloadFilesInChunks(
      List<ARFSFileEntity> files, DownloadService downloadService) async {
    const chunkSize = 25;

    final chunks = List<List<ARFSFileEntity>>.generate(
        (files.length / chunkSize).ceil(),
        (i) => files.sublist(
            i * chunkSize,
            (i + 1) * chunkSize < files.length
                ? (i + 1) * chunkSize
                : files.length));

    final ioFiles = <IOFile>[];

    await Future.forEach(chunks, (List<ARFSFileEntity> chunk) async {
      final futures = <Future>[];
      for (final file in chunk) {
        final future =
            downloadService.download(file.txId).then((dataBytes) async {
          final ioFile = await IOFile.fromData(
            dataBytes,
            name: file.name,
            lastModifiedDate: file.lastModifiedDate,
          );
          ioFiles.add(ioFile);
        });
        futures.add(future);
      }
      await Future.wait(futures);
    });

    return ioFiles;
  }

  bool _isSizeAbovePublicLimit(int size) {
    return size > const GiB(1).size;
  }
}
