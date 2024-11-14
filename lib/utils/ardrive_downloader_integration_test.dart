import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:cryptography/cryptography.dart';

class ArDriveIODownloaderIntegrationTest implements ArDriveIODownloader {
  @override
  Future<void> cancelDownload() {
    throw UnimplementedError();
  }

  @override
  Stream<int> downloadFile(
      String downloadUrl, String fileName, String? contentType) {
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() {
    return Future.value();
  }

  @override
  Future<void> openCurrentDownload() {
    throw UnimplementedError();
  }
}

class ArDriveFileDownloaderIntegrationTest implements ArDriveFileDownloader {
  @override
  Future<void> abortDownload() async {}

  @override
  Future<Stream<double>> downloadFile({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async {
    return const Stream.empty();
  }

  @override
  Future<Uint8List> downloadToMemory({
    required TransactionCommonMixin dataTx,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
  }) async {
    return Uint8List(0);
  }
}
