import 'package:arconnect/arconnect.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

/// A utility class to manage signature headers for Turbo uploads.
/// This class caches the signature headers in memory to avoid multiple
/// sign requests, but verifies the wallet address hasn't changed.
class TurboSignatureHeadersManager {
  static TurboSignatureHeadersManager? _instance;
  Map<String, dynamic>? _cachedHeaders;
  String? _lastWalletAddress;
  final TabVisibilitySingleton _tabVisibility;

  TurboSignatureHeadersManager._({
    required TabVisibilitySingleton tabVisibility,
  }) : _tabVisibility = tabVisibility;

  static TurboSignatureHeadersManager getInstance({
    required TabVisibilitySingleton tabVisibility,
  }) {
    _instance ??= TurboSignatureHeadersManager._(
      tabVisibility: tabVisibility,
    );
    return _instance!;
  }

  /// Gets signature headers for Turbo uploads.
  /// Headers are cached in memory to avoid multiple sign requests.
  /// The cache is invalidated if the wallet address changes.
  ///
  /// [wallet] The wallet to use for signing.
  Future<Map<String, dynamic>> getSignatureHeaders({
    Wallet? wallet,
  }) async {
    if (wallet == null) {
      return {};
    }

    try {
      // Get current wallet address
      final currentAddress = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Getting wallet address with safe ArConnect action');
          return wallet.getAddress();
        },
      );

      // If we have cached headers and the wallet address is the same, return the cached headers
      if (_cachedHeaders != null && _lastWalletAddress == currentAddress) {
        logger.d('Using cached signature headers for Turbo');
        return _cachedHeaders!;
      }

      // Generate new headers
      logger.d('Generating new signature headers for Turbo');
      final nonce = const Uuid().v4();
      final publicKey = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Getting public key with safe ArConnect action');
          return wallet.getOwner();
        },
      );

      final signature = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Signing with safe ArConnect action');
          return signNonceAndData(
            nonce: nonce,
            wallet: wallet,
          );
        },
      );

      // Cache the headers and wallet address
      _cachedHeaders = {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      };
      _lastWalletAddress = currentAddress;

      logger.d('Generated new signature headers for Turbo');
      return _cachedHeaders!;
    } catch (e, stacktrace) {
      logger.e('Error generating signature headers for Turbo', e, stacktrace);
      throw Exception('Failed to generate signature headers: $e');
    }
  }
}
