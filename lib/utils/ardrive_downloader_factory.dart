import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/ardrive_downloader_integration_test.dart';
import 'package:ardrive/utils/integration_tests_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';

class ArDriveIODownloaderFactory {
  static ArDriveIODownloader createArDriveDownloader() {
    if (isIntegrationTest()) {
      return ArDriveIODownloaderIntegrationTest();
    }

    return ArDriveMobileDownloader();
  }
}

class ArDriveFileDownloaderFactory {
  static ArDriveFileDownloader createArDriveFileDownloader({
    required ArDriveIO ardriveIo,
    required ArweaveService arweave,
    required IOFileAdapter ioFileAdapter,
  }) {
    if (isIntegrationTest()) {
      return ArDriveFileDownloaderIntegrationTest();
    }

    return ArDriveFileDownloader(
      ardriveIo: ardriveIo,
      arweave: arweave,
      ioFileAdapter: ioFileAdapter,
    );
  }
}
