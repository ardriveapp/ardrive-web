import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/cost_calculator.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service.dart';
import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:pst/pst.dart';

class _DataBundlerFactory implements DataBundlerFactory {
  final ARFSUploadMetadataGenerator metadataGenerator;
  final Arweave arweaveService;
  final PstService pstService;

  _DataBundlerFactory({
    required this.metadataGenerator,
    required this.arweaveService,
    required this.pstService,
  });

  @override
  DataBundler createDataBundler(UploadType type) {
    switch (type) {
      case UploadType.turbo:
        return BDIDataBundler(metadataGenerator);
      case UploadType.d2n:
        return DataTransactionBundler(
          metadataGenerator,
          UploadCostEstimateCalculatorForAR(
            arCostToUsd: ConvertArToUSD(),
            arweaveService: arweaveService,
            pstService: pstService,
          ),
          pstService,
        );
      default:
        throw Exception('Invalid upload type');
    }
  }
}

abstract class DataBundlerFactory {
  DataBundler createDataBundler(UploadType type);

  factory DataBundlerFactory({
    required Arweave arweaveService,
    required PstService pstService,
    required ARFSUploadMetadataGenerator metadataGenerator,
  }) {
    return _DataBundlerFactory(
      metadataGenerator: metadataGenerator,
      arweaveService: arweaveService,
      pstService: pstService,
    );
  }
}

abstract class UploadFileStrategyFactory {
  UploadFileStrategy createUploadStrategy({
    required UploadType type,
  });

  factory UploadFileStrategyFactory(DataBundlerFactory dataBundlerFactory,
      StreamedUploadFactory streamedUploadFactory) {
    return _UploadFileStrategyFactory(
        dataBundlerFactory, streamedUploadFactory);
  }
}

class _UploadFileStrategyFactory implements UploadFileStrategyFactory {
  final DataBundlerFactory _dataBundlerFactory;
  final StreamedUploadFactory _streamedUploadFactory;

  _UploadFileStrategyFactory(
      this._dataBundlerFactory, this._streamedUploadFactory);

  @override
  UploadFileStrategy createUploadStrategy({
    required UploadType type,
  }) {
    switch (type) {
      case UploadType.turbo:
        return UploadFileUsingDataItemFiles(
            streamedUploadFactory: _streamedUploadFactory);
      case UploadType.d2n:
        return UploadFileUsingBundleStrategy(
          dataBundler: _dataBundlerFactory.createDataBundler(type),
          streamedUploadFactory: _streamedUploadFactory,
        );
      default:
        throw Exception('Invalid upload type');
    }
  }
}

class StreamedUploadFactory {
  final Uri turboUploadUri;

  StreamedUploadFactory({
    required this.turboUploadUri,
  });

  Future<StreamedUpload> fromUploadType(
    UploadTask task,
  ) async {
    if (task.type == UploadType.d2n) {
      return D2NStreamedUpload();
    } else if (task.type == UploadType.turbo) {
      bool useMultipart;

      if (task is FileUploadTask) {
        final fileSize = await (task).file.length;

        if (fileSize >= MiB(5).size) {
          useMultipart = true;
        } else {
          useMultipart = false;
        }
      } else {
        /// Non-file uploads e.g. folder uploads (bundle of folders metadata)
        /// are always chunked
        useMultipart = false;
      }

      logger.i('useMultipart: $useMultipart');

      return TurboStreamedUpload(
        TurboUploadServiceFactory().createTurboUploadService(
          useMultipart,
          turboUploadUri,
        ),
      );
    } else {
      throw Exception('Invalid upload type');
    }
  }
}

class TurboUploadServiceFactory {
  TurboUploadService createTurboUploadService(
      bool isMultipart, Uri turboUploadUri) {
    if (isMultipart) {
      return TurboUploadServiceMultipart(turboUploadUri: turboUploadUri);
    } else {
      return TurboUploadServiceChunked(turboUploadUri: turboUploadUri);
    }
  }
}
