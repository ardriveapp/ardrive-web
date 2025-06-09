import 'dart:typed_data';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:pub_semver/pub_semver.dart';

import 'implementations/arconnect_web.dart'
    if (dart.library.io) 'implementations/arconnect_stub.dart'
    as implementation;

class ArConnectService {
  Future<bool>? _walletVersionSupportedFuture;

  /// Returns true is the ArConnect browser extension is installed and available
  bool isExtensionPresent() => implementation.isExtensionPresent();

  /// Connects with ArConnect. If the user is not logged into it, asks user to login and
  /// requests permissions.
  Future<void> connect() => implementation.connect();

  /// Returns true if necessary permissions have been provided
  Future<bool> checkPermissions() => implementation.checkPermissions();

  /// Disonnects from the extensions and revokes permissions
  Future<void> disconnect() => implementation.disconnect();

  /// Posts a 'walletSwitch' message to the window.parent DOM object when a wallet
  /// switch occurs
  void listenForWalletSwitch() => implementation.listenForWalletSwitch();

  /// Returns the wallet address
  Future<String> getWalletAddress() => implementation.getWalletAddress();

  /// Returns the wallet public key
  Future<String> getPublicKey() async => await implementation.getPublicKey();

  /// Takes a message and returns the signature
  Future<Uint8List> getSignature(Uint8List message) async =>
      await implementation.getSignature(message);

  /// Takes a DataItem and returns the signature bytes
  Future<Uint8List> signDataItem(DataItem dataItem) async =>
      await implementation.signDataItem(dataItem);

  Future<bool> isWalletVersionSupported() {
    if (_walletVersionSupportedFuture != null) {
      return _walletVersionSupportedFuture!;
    }

    _walletVersionSupportedFuture = _checkWalletVersion();
    return _walletVersionSupportedFuture!;
  }

  Future<bool> _checkWalletVersion() async {
    final versionString = await implementation.getWalletVersion();
    try {
      final version = Version.parse(versionString);

      const minMobileAppVersion = '2.5.0';
      const minBrowserExtensionVersion = '1.26.0';

      final minVersion = AppPlatform.isMobileWeb()
          ? minMobileAppVersion
          : minBrowserExtensionVersion;
      final constraint = VersionConstraint.parse('>= $minVersion');

      return constraint.allows(version);
    } catch (e) {
      return false;
    }
  }
}
