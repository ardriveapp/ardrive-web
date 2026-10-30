import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';

class ArConnectWallet extends Wallet {
  ArConnectWallet(this.arConnectService, {this.publicKey});

  final ArConnectService arConnectService;

  /// The saved account's public key, when this wallet was loaded from it.
  ///
  /// Then the owner and address are known here and Wander is asked only to
  /// sign, with a deadline (see [ArConnectPrompt]), so a locked Wander can't
  /// hold up unlocking, a sync or a read. A Wander on another wallet is
  /// caught before a write by `ProfileCubit.checkIfWalletMismatch`.
  ///
  /// Null while connecting at login, where Wander is the only source and the
  /// sign-in panel has its own Cancel.
  final String? publicKey;

  @override
  Future<String> getOwner() async {
    return publicKey ?? await arConnectService.getPublicKey();
  }

  @override
  Future<String> getAddress() async {
    final savedPublicKey = publicKey;
    if (savedPublicKey != null) return ownerToAddress(savedPublicKey);
    return await arConnectService.getWalletAddress();
  }

  /// [request] with a deadline and Try again, for the saved account's
  /// wallet; as before while connecting at login.
  Future<T> _ask<T>(Future<T> Function() request) {
    if (publicKey == null) return request();
    return ArConnectPrompt.ask(
      arConnectService,
      request,
      within: ArConnectPrompt.signTimeout,
    );
  }

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async {
    logger.d('ArConnectWallet.sign() called with ${message.length} bytes'
        '${context != null ? ' (context: $context)' : ''}');
    try {
      final result = await _ask(() => arConnectService.getSignature(message));
      logger.d('ArConnectWallet.sign() successful, got ${result.length} bytes');
      return result;
    } catch (e, stackTrace) {
      logger.e('ArConnectWallet.sign() failed', e, stackTrace);
      rethrow;
    }
  }

  /// Whether Wander can sign several data items in one approval.
  bool get canBatchSign {
    try {
      return arConnectService.isBatchSignSupported();
    } catch (_) {
      return false;
    }
  }

  /// Signs [dataItems] in one Wander approval and returns each one's
  /// signature in order. Asked like [signDataItem], with the same deadline,
  /// so a batch Wander never answers ends in the same Try again prompt.
  Future<List<Uint8List>> batchSignDataItems(List<DataItem> dataItems) async {
    logger.d('ArConnectWallet.batchSignDataItems() called with '
        '${dataItems.length} items');
    try {
      final result =
          await _ask(() => arConnectService.batchSignDataItems(dataItems));
      logger.d('ArConnectWallet.batchSignDataItems() successful, got '
          '${result.length} signatures');
      return result;
    } catch (e, stackTrace) {
      logger.e('ArConnectWallet.batchSignDataItems() failed', e, stackTrace);
      rethrow;
    }
  }

  /// Signs a [DataItem] via ArConnect. Not part of the arweave [Wallet] interface.
  Future<Uint8List> signDataItem(DataItem dataItem) async {
    logger.d(
        'ArConnectWallet.signDataItem() called with ${dataItem.data.length} bytes');
    try {
      final result = await _ask(() => arConnectService.signDataItem(dataItem));
      logger.d(
          'ArConnectWallet.signDataItem() successful, got ${result.length} bytes');
      return result;
    } catch (e, stackTrace) {
      logger.e('ArConnectWallet.signDataItem() failed', e, stackTrace);
      rethrow;
    }
  }
}
