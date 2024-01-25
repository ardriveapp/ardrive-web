import 'package:arconnect/arconnect.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

Future<Map<String, dynamic>> getHeadersForTurboStreamedUpload({
  required Wallet wallet,
  required TabVisibilitySingleton tabVisibility,
}) async {
  final nonce = const Uuid().v4();

  final publicKey = await safeArConnectAction<String>(
    tabVisibility,
    (_) async {
      return wallet.getOwner();
    },
  );

  final signature = await safeArConnectAction<String>(
    tabVisibility,
    (_) async {
      return signNonceAndData(
        nonce: nonce,
        wallet: wallet,
      );
    },
  );

  return {
    'x-nonce': nonce,
    'x-address': publicKey,
    'x-signature': signature,
  };
}
