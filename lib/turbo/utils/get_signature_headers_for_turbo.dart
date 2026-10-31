import 'package:arconnect/arconnect.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
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

  /// Bumped whenever the cache is cleared, so a signature that was still
  /// being made at the time is not stored afterwards: it would put a signed
  /// header back in memory after a sign-out.
  int _generation = 0;
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

  /// Forgets the signed headers, so the next read signs afresh. Called when
  /// Turbo refuses them, and on sign-out.
  void clearCache() {
    _generation++;
    _cachedHeaders = null;
    _lastWalletAddress = null;
  }

  /// [clearCache] on the shared instance, if one was ever made.
  static void clearSession() => _instance?.clearCache();

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

    final generation = _generation;

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

      final headers = {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      };

      // Cache them, unless the cache was cleared while they were signed.
      if (generation == _generation) {
        _cachedHeaders = headers;
        _lastWalletAddress = currentAddress;
      }

      logger.d('Generated new signature headers for Turbo');
      return headers;
    } catch (e, stacktrace) {
      logger.e('Error generating signature headers for Turbo', e, stacktrace);
      throw TurboSignatureException('Failed to generate signature headers: $e');
    }
  }
}
