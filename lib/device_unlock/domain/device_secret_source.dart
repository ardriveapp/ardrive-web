import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart'
    show isWalletCancellation;
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;

/// The person said no to the wallet prompt for the device key, or Wander
/// could not be reached and they chose not to try again. Remembered values
/// stay closed; drives show as locked.
class DeviceUnlockDeclined implements Exception {
  const DeviceUnlockDeclined();
}

/// The wallet could not sign for another reason.
class DeviceUnlockFailed implements Exception {
  const DeviceUnlockFailed(this.reason);

  final String reason;

  @override
  String toString() => 'DeviceUnlockFailed($reason)';
}

/// Where a session's device key comes from: the secret that, with the device
/// salt, derives it. One per account type; see [DeviceUnlockMethod].
///
/// Each source makes one request. A batch path (one wallet approval for the
/// device key and several drive keys) can build the same request through
/// [WanderDeviceSecret.unlockItem] and hand the signature to
/// [DeviceSecretSource.fromSecret].
abstract class DeviceSecretSource {
  DeviceUnlockMethod get method;

  /// The secret for [deviceSalt]. Throws [DeviceUnlockDeclined] when the
  /// person says no, and [DeviceUnlockFailed] when the wallet can't sign.
  Future<Uint8List> secret(Uint8List deviceSalt);

  /// A secret already in hand, such as the Phantom sign-in signature, or one
  /// a batch request returned.
  static DeviceSecretSource fromSecret(
    DeviceUnlockMethod method,
    Uint8List secret,
  ) =>
      _GivenSecret(method, secret);
}

class _GivenSecret implements DeviceSecretSource {
  _GivenSecret(this.method, this._secret);

  @override
  final DeviceUnlockMethod method;
  final Uint8List _secret;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async => _secret;
}

/// The device password: its PBKDF2 key under the profile's key salt, as the
/// profile has always derived it.
class PasswordDeviceSecret implements DeviceSecretSource {
  PasswordDeviceSecret({required this.password, required this.keySalt});

  final String password;
  final List<int> keySalt;

  @override
  DeviceUnlockMethod get method => DeviceUnlockMethod.password;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async {
    final derived = await ArDriveCrypto().deriveProfileKey(password, keySalt);
    return Uint8List.fromList(await derived.key.extractBytes());
  }
}

/// Wander: one `signDataItem` (salt length 0, so the same item always gets
/// the same signature) of a fixed item tagged `App-Name: ArDrive`,
/// `Action: Unlock-Device-V1`, whose data is the device salt.
///
/// Asked through [ArConnectWallet.signDataItem], which gives a saved
/// account's Wander a deadline and Try again ([ArConnectPrompt]), so a
/// locked Wander or a closed prompt can't leave the app waiting.
class WanderDeviceSecret implements DeviceSecretSource {
  WanderDeviceSecret(this.wallet);

  final Wallet wallet;

  @override
  DeviceUnlockMethod get method => DeviceUnlockMethod.wander;

  /// The item signed. Nothing in it changes between requests: no anchor, no
  /// target, the tags in this order.
  static Future<DataItem> unlockItem(
      Wallet wallet, Uint8List deviceSalt) async {
    final item = DataItem.withBlobData(
      data: deviceSalt,
      owner: await wallet.getOwner(),
    );
    wanderDeviceUnlockTags.forEach(item.addTag);
    return item;
  }

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async {
    final item = await unlockItem(wallet, deviceSalt);
    try {
      final w = wallet;
      if (w is ArConnectWallet) {
        return await w.signDataItem(item);
      }
      await item.sign(ArweaveSigner(w));
      return utils.decodeBase64ToBytes(item.signature);
    } on ArConnectUnavailableException {
      throw const DeviceUnlockDeclined();
    } catch (e) {
      if (isWalletCancellation(e)) throw const DeviceUnlockDeclined();
      throw DeviceUnlockFailed('$e');
    }
  }
}

/// Phantom and Solflare: the sign-in signature, which the sign-in already
/// asks for, so the device key costs no extra prompt.
class SolanaDeviceSecret implements DeviceSecretSource {
  SolanaDeviceSecret(this._signIn);

  /// Returns the signature of `solanaIdentityMessage`.
  final Future<Uint8List> Function() _signIn;

  @override
  DeviceUnlockMethod get method => DeviceUnlockMethod.solana;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async {
    try {
      return await _signIn();
    } catch (e) {
      if (isWalletCancellation(e)) throw const DeviceUnlockDeclined();
      throw DeviceUnlockFailed('$e');
    }
  }
}

/// MetaMask: a `personal_sign` of [ethereumDeviceUnlockMessage].
class EthereumDeviceSecret implements DeviceSecretSource {
  EthereumDeviceSecret(this.wallet);

  final EthereumWallet wallet;

  @override
  DeviceUnlockMethod get method => DeviceUnlockMethod.ethereum;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async {
    final message = ethereumDeviceUnlockMessage(await wallet.getAddress());
    try {
      return await wallet.sign(Uint8List.fromList(utf8.encode(message)));
    } catch (e) {
      if (isWalletCancellation(e)) throw const DeviceUnlockDeclined();
      throw DeviceUnlockFailed('$e');
    }
  }
}
