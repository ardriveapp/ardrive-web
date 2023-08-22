import 'dart:convert';
import 'dart:isolate';

import 'package:arweave/arweave.dart';

void heavyComputationTask(SendPort sendPort) async {
  ReceivePort walletGeneratorReceivePort = ReceivePort();
  sendPort.send(walletGeneratorReceivePort.sendPort);

  await for (var message in walletGeneratorReceivePort) {
    if (message is List) {
      final mnemonic = message[0];
      final SendPort walletGeneratorResponseSendPort = message[1];

      final wallet = await Wallet.createWalletFromMnemonic(mnemonic);

      walletGeneratorResponseSendPort.send(jsonEncode(wallet.toJwk()));
    }
  }

  sendPort.send('result');
}

Future<Wallet> generateWalletFromMnemonic(String mnemonic) async {
  ReceivePort myReceivePort = ReceivePort();
  Isolate.spawn<SendPort>(heavyComputationTask, myReceivePort.sendPort);

  SendPort walletGeneratorSendPort = await myReceivePort.first;
  ReceivePort walletGeneratorReceivePort = ReceivePort();

  walletGeneratorSendPort.send([mnemonic, walletGeneratorReceivePort.sendPort]);

  final walletJsonStr = await walletGeneratorReceivePort.first as String;
  final wallet = Wallet.fromJwk(jsonDecode(walletJsonStr));

  return wallet;
}
