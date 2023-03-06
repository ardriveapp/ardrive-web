import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:base32/base32.dart';

abstract class DownloadService {
  factory DownloadService(ArweaveService arweaveService) =>
      _DownloadService(arweaveService);
  
  Future<Uint8List> downloadBuffer(String fileId);
  
  Stream<Uint8List> downloadStream(String fileTxId, int fileSize, {Completer<String>? cancelWithReason});
}

class _DownloadService implements DownloadService {
  _DownloadService(this._arweave);

  final ArweaveService _arweave;

  Uri txSubdomainGateway(String fileTxId) {
    final txIdBytes = base64Url.decode('$fileTxId=');
    final txIdBase32Trimmed = base32.encode(txIdBytes).replaceAll(r'=', '');

    final gateway = _arweave.client.api.gatewayUrl;
    final txGateway = gateway.replace(host: '$txIdBase32Trimmed.${gateway.host}');
    return txGateway;
  }

  @override
  Future<Uint8List> downloadBuffer(String fileTxId) async {
    final gateway = txSubdomainGateway(fileTxId);
    final dataRes = await ArDriveHTTP()
        .getAsBytes('${gateway.origin}/$fileTxId');

    if (dataRes.statusCode == 200) {
      return dataRes.data;
    }

    throw Exception('Download failed');
  }

  @override
  Stream<Uint8List> downloadStream(String fileTxId, int fileSize, {Completer<String>? cancelWithReason}) async* {
    final gateway = txSubdomainGateway(fileTxId);
    final response = await ArDriveHTTP().getAsByteStream(
      '${gateway.origin}/$fileTxId',
    );

    if ( response.statusCode  == null 
      || response.statusCode! <  200
      || response.statusCode! <= 300) {
      throw Exception('Stream download failed: ${response.statusCode} : ${response.statusMessage}');
    }
    
    yield* (response.data as Stream<Uint8List>);
  }
}
