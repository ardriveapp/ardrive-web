import 'package:arconnect/arconnect.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:pst/pst.dart';

abstract class BundleSigner<T> {
  Future<T> signBundle({required DataBundle unSignedBundle});
}

class BDISigner implements BundleSigner<DataItem> {
  final ArweaveService arweaveService;
  final Wallet wallet;

  BDISigner({
    required this.arweaveService,
    required this.wallet,
  });

  @override
  Future<DataItem> signBundle({required DataBundle unSignedBundle}) async {
    logger.i('Preparing bundle data item');

    final bundleDataItem = await arweaveService.prepareBundledDataItem(
      unSignedBundle,
      wallet,
    );

    logger.i('Bundle data item created');

    return bundleDataItem;
  }
}

abstract class BundleTransactionSigner<Transaction> extends BundleSigner {
  @override
  Future<Transaction> signBundle({required DataBundle unSignedBundle});
}

class ArweaveBundleTransactionSigner implements BundleTransactionSigner {
  final ArweaveService arweaveService;
  final PstService pstService;
  final Wallet wallet;

  ArweaveBundleTransactionSigner({
    required this.arweaveService,
    required this.wallet,
    required this.pstService,
  });

  @override
  Future<Transaction> signBundle({required DataBundle unSignedBundle}) async {
    final bundleTx = await arweaveService.prepareDataBundleTxFromBlob(
      unSignedBundle.blob,
      wallet,
    );
    logger.i('Bundle transaction created');

    logger.i('Adding tip...');

    try {
      await pstService.addCommunityTipToTx(bundleTx);
    } catch (e) {
      logger.e('Error adding community tip to transaction. Proceeding.', e);
    }

    logger.i('Tip added');

    logger.i('Signing bundle...');

    await bundleTx.sign(ArweaveSigner(wallet));

    logger.i('Bundle signed');

    return bundleTx;
  }
}

class SafeArConnectSigner<T> extends BundleSigner<T> {
  final TabVisibilitySingleton _tabVisibilitySingleton;

  final BundleSigner bundleSigner;

  SafeArConnectSigner(this.bundleSigner,
      {TabVisibilitySingleton? tabVisibility})
      : _tabVisibilitySingleton = tabVisibility ?? TabVisibilitySingleton();

  @override
  Future<T> signBundle({required DataBundle unSignedBundle}) async {
    final T signedItem = await safeArConnectAction<T>(
      _tabVisibilitySingleton,
      (_) async {
        logger.d('Signing bundle with safe ArConnect action');
        return await bundleSigner.signBundle(unSignedBundle: unSignedBundle);
      },
    );

    return signedItem;
  }
}

class SafeArConnectBDISigner extends SafeArConnectSigner<DataItem> {
  SafeArConnectBDISigner(BDISigner super.bundleSigner);
}

class SafeArConnectTransactionSigner extends SafeArConnectSigner<Transaction> {
  SafeArConnectTransactionSigner(super.bundleSigner);
}

class SafeArConnectArweaveBundleTransactionSigner
    extends SafeArConnectSigner<Transaction> {
  SafeArConnectArweaveBundleTransactionSigner(
      BundleTransactionSigner super.bundleSigner);
}
