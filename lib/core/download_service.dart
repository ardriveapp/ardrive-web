import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';

abstract class DownloadService {
  Future<Uint8List> download(String fileTxId, bool isManifest);
  Future<Stream<List<int>>> downloadStream(String fileTxId, bool isManifest);

  factory DownloadService(ArweaveService arweaveService) =>
      _DownloadService(arweaveService);
}

/// Every fetch here goes through [DataGatewayFallback], the same waterfall
/// (primary → GAR → arweave.net) the rest of the app reads data with.
///
/// This used to name one gateway by hand, which made a manifest import, a
/// multi-file download, or a password login fail outright whenever the
/// configured gateway was down - even though the data was sitting on every
/// other gateway in the network.
class _DownloadService implements DownloadService {
  _DownloadService(this._arweave);

  final ArweaveService _arweave;

  @override
  Future<Uint8List> download(String fileTxId, bool isManifest) async {
    // A manifest has to be read from `/raw/`, or the gateway resolves it to the
    // file its index points at instead of handing back the manifest itself.
    if (isManifest) {
      final response = await _arweave.gatewayFallback.fetchManifestWithFallback(
        fileTxId,
        _arweave.client,
      );

      return response.bodyBytes;
    }

    // Deliberately not `fetchData`: this call carries whole files - a
    // multi-file download reaches for hundreds of megabytes - and `fetchData`
    // caps a gateway attempt at five seconds of *body*, which no such transfer
    // would survive.
    return _arweave.gatewayFallback.fetchFileData(fileTxId, _arweave.client);
  }

  @override
  Future<Stream<List<int>>> downloadStream(
      String fileTxId, bool isManifest) async {
    if (isManifest) {
      final data = await download(fileTxId, true);
      return Stream.fromIterable([data.toList()]);
    }

    final (stream, _) = await _arweave.gatewayFallback.downloadWithFallback(
      txId: fileTxId,
      primaryClient: _arweave.client,
    );

    return stream;
  }
}
