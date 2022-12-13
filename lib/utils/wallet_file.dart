import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';

class WalletFile extends IOFile {
  final Wallet wallet;
  final String address;
  WalletFile(
    this.wallet,
    this.address,
  ) : super(contentType: 'application/json');
  @override
  DateTime get lastModifiedDate => DateTime.now();

  @override
  FutureOr<int> get length => json.encode(wallet.toJwk()).length;

  @override
  String get name => 'ArDrive-Wallet-$address';

  @override
  String get path => throw UnimplementedError();

  @override
  Future<Uint8List> readAsBytes() async {
    return Uint8List.fromList(json.encode(wallet.toJwk()).codeUnits);
  }

  @override
  Future<String> readAsString() async {
    return json.encode(wallet.toJwk());
  }
}
