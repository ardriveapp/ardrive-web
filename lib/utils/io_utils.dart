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
  Future<bool> downloadWalletAsJsonFile({
    required Wallet wallet,
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
      await io.saveFile(file);
      return true;
    } catch (e) {
      return false;
    }
  }
}
