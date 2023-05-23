import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_http/ardrive_http.dart';

abstract class DownloadService {
  Future<Uint8List> download(String fileId);
  factory DownloadService(ArweaveService arweaveService) =>
      _DownloadService(arweaveService);
}

class _DownloadService implements DownloadService {
  _DownloadService(this._arweave);

  final ArweaveService _arweave;

  @override
  Future<Uint8List> download(String fileTxId) async {
    final dataRes = await ArDriveHTTP()
        .getAsBytes('${_arweave.client.api.gatewayUrl.origin}/$fileTxId');

    if (dataRes.statusCode == 200) {
      return dataRes.data;
    }

    throw Exception('Download failed');
  }
}
