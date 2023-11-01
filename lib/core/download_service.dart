import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart' as arweave;

abstract class DownloadService {
  Future<Uint8List> download(String fileTxId, bool isManifest);
  Future<Stream<List<int>>> downloadStream(String fileTxId, bool isManifest);

  factory DownloadService(ArweaveService arweaveService) =>
      _DownloadService(arweaveService);
}

class _DownloadService implements DownloadService {
  _DownloadService(this._arweave);

  final ArweaveService _arweave;

  @override
  Future<Uint8List> download(String fileTxId, bool isManifest) async {
    final urlString = isManifest
        ? '${_arweave.client.api.gatewayUrl.origin}/raw/$fileTxId'
        : '${_arweave.client.api.gatewayUrl.origin}/$fileTxId';

    final dataRes = await ArDriveHTTP().getAsBytes(urlString);

    if (dataRes.statusCode == 200) {
      return dataRes.data;
    }

    throw Exception('Download failed');
  }

  @override
  Future<Stream<List<int>>> downloadStream(
      String fileTxId, bool isManifest) async {
    if (isManifest) {
      final data = await download(fileTxId, true);
      return Stream.fromIterable([data.toList()]);
    }

    final downloadResponse = await arweave.download(txId: fileTxId);

    return downloadResponse.$1;
  }
}
