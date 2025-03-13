import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';

class ArDriveIOUtils {
  final ArDriveIO io;
  final IOFileAdapter fileAdapter;

  ArDriveIOUtils({
    ArDriveIO? io,
    IOFileAdapter? fileAdapter,
  })  : io = io ?? ArDriveIO(),
        fileAdapter = fileAdapter ?? IOFileAdapter();

  /// Download the wallet as a json file
  /// Throws an exception if the wallet is an ArConnect wallet
  ///
  /// Returns a Future that completes when the download is finished
  ///
  /// If provided, the [onDownloadComplete] callback will be called with a boolean
  /// indicating whether the download was successful
  Future<void> downloadWalletAsJsonFile({
    required Wallet wallet,
    void Function(bool success)? onDownloadComplete,
  }) async {
    if (wallet is ArConnectWallet) {
      throw Exception('ArConnect wallet not supported');
    }

    final jsonTxt = jsonEncode(wallet.toJwk());

    final bytes = Uint8List.fromList(utf8.encode(jsonTxt));

    final file = await fileAdapter.fromData(
      bytes,
      name: 'ardrive-wallet.json',
      contentType: 'application/json',
      lastModifiedDate: DateTime.now(),
    );

    try {
      final result = await io.saveFile(file);
      if (onDownloadComplete != null) {
        onDownloadComplete(true);
      }
      return result;
    } catch (e) {
      if (onDownloadComplete != null) {
        onDownloadComplete(false);
      }
      rethrow;
    }
  }
}
