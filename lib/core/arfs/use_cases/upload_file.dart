import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:pst/pst.dart';

/// Result of a file upload operation
class FileUploadResult {
  final String dataTxId;
  final String contentType;
  final int size;

  FileUploadResult({
    required this.dataTxId,
    required this.contentType,
    required this.size,
  });
}

/// Use case for uploading files to Arweave
class UploadFile {
  final ArweaveService _arweaveService;
  final Arweave _arweave;
  final PstService _pstService;
  final Wallet _wallet;

  UploadFile({
    required ArweaveService arweaveService,
    required Arweave arweave,
    required PstService pstService,
    required Wallet wallet,
  })  : _arweaveService = arweaveService,
        _arweave = arweave,
        _pstService = pstService,
        _wallet = wallet;

  /// Uploads a file to Arweave and returns the upload result
  ///
  /// [fileHandle] - The file handle containing the file data and metadata
  /// [onProgress] - Optional callback for upload progress updates
  Future<FileUploadResult> call({
    required FileV2UploadHandle fileHandle,
    void Function(double progress)? onProgress,
  }) async {
    try {
      logger.i('Starting file upload: ${fileHandle.entity.name}');

      // Prepare and sign the transactions
      await fileHandle.prepareAndSignTransactions(
        arweaveService: _arweaveService,
        wallet: _wallet,
        pstService: _pstService,
      );

      // Upload the file data
      await _arweaveService.postTx(fileHandle.entityTx);

      final uploadStream = _arweave.transactions.upload(
        fileHandle.dataTx,
        maxConcurrentUploadCount: 1,
      );

      await for (final upload in uploadStream) {
        onProgress?.call(upload.progress);
        fileHandle.uploadProgress = upload.progress;
      }

      logger.i('File upload completed: ${fileHandle.entity.name}');

      return FileUploadResult(
        dataTxId: fileHandle.dataTx.id,
        contentType:
            fileHandle.entity.dataContentType ?? 'application/octet-stream',
        size: fileHandle.size,
      );
    } catch (e) {
      logger.e('File upload failed: ${fileHandle.entity.name}', e);
      throw Exception('Failed to upload file: ${e.toString()}');
    }
  }
}
