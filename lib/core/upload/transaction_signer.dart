import 'package:arconnect/arconnect.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pst/pst.dart';

abstract class TransactionSigner {
  Future<SignedTransactionInfo> signTransaction({
    required bool isPrivate,
    required IOFile file,
    SecretKey? fileKey,
    required FileEntity entity,
  });
}

class ArweaveTransactionSigner implements TransactionSigner {
  final ArDriveCrypto crypto;
  final ArweaveService arweaveService;
  final PstService pstService;
  final Wallet wallet;

  ArweaveTransactionSigner({
    required this.crypto,
    required this.arweaveService,
    required this.pstService,
    required this.wallet,
  });

  @override
  Future<SignedTransactionInfo> signTransaction({
    required bool isPrivate,
    required IOFile file,
    SecretKey? fileKey,
    required FileEntity entity,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final String version = packageInfo.version;

    Transaction transaction;
    Transaction dataTx;
    Transaction entityTx;

    if (isPrivate) {
      transaction = await crypto.createEncryptedTransaction(
        await file.readAsBytes(),
        fileKey!,
      );
    } else {
      transaction = TransactionStream.withBlobData(
        dataStreamGenerator: file.openReadStream,
        dataSize: await file.length,
      );
    }

    dataTx = await arweaveService.client.transactions.prepare(
      transaction,
      wallet,
    )
      ..addApplicationTags(version: version)
      ..addUTags();

    try {
      await pstService.addCommunityTipToTx(dataTx);
    } catch (e) {
      logger.e('Error adding community tip to transaction. Proceeding.', e);
    }

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataTx.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataTx.sign(ArweaveSigner(wallet));

    entity.dataTxId = dataTx.id;
    entityTx = await arweaveService.prepareEntityTx(entity, wallet, fileKey);
    entity.txId = entityTx.id;

    return SignedTransactionInfo(
      dataTx: dataTx,
      entityTx: entityTx,
      entity: entity,
    );
  }
}

class SafeArConnectTransactionSigner extends ArweaveTransactionSigner {
  SafeArConnectTransactionSigner({
    required super.crypto,
    required super.arweaveService,
    required super.pstService,
    required super.wallet,
  });

  final TabVisibilitySingleton tabVisibilitySingleton =
      TabVisibilitySingleton();

  @override
  Future<SignedTransactionInfo> signTransaction({
    required bool isPrivate,
    required IOFile file,
    SecretKey? fileKey,
    required FileEntity entity,
  }) async {
    final signedItem = await safeArConnectAction(
      tabVisibilitySingleton,
      (_) async {
        logger.d('Signing transaction with safe ArConnect action');
        return super.signTransaction(
          isPrivate: isPrivate,
          file: file,
          fileKey: fileKey,
          entity: entity,
        );
      },
    );

    return signedItem;
  }
}

class SignedTransactionInfo {
  final Transaction dataTx;
  final Transaction entityTx;
  final FileEntity entity;

  SignedTransactionInfo({
    required this.dataTx,
    required this.entityTx,
    required this.entity,
  });
}
