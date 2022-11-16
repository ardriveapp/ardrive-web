import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:http/http.dart' as http;

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
    final dataRes = await http.get(
      Uri.parse(
        '${_arweave.client.api.gatewayUrl.origin}/$fileTxId',
      ),
    );

    if (dataRes.statusCode == 200) {
      return dataRes.bodyBytes;
    }

    throw Exception('Download failed');
  }
}
