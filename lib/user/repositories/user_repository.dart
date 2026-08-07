import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';

abstract class UserRepository {
  Future<bool> hasUser();
  Future<User?> getUser(String password);
  Future<void> saveUser(
    String password,
    ProfileType profileType,
    Wallet wallet, {
    String? sourceWalletAddress,
  });
  Future<void> deleteUser();
  Future<String?> getOwnerOfDefaultProfile();
  Future<BigInt> getBalance(Wallet wallet);
  Future<String?> getARIOTokens(Wallet wallet);

  factory UserRepository(
          ProfileDao profileDao, ArweaveService arweave, ArioSDK arioSDK) =>
      _UserRepository(
        profileDao: profileDao,
        arweave: arweave,
        arioSDK: arioSDK,
      );
}

class _UserRepository implements UserRepository {
  static const _walletBalanceLoginTimeout = Duration(seconds: 5);

  final ProfileDao _profileDao;
  final ArweaveService _arweave;
  final ArioSDK _arioSDK;

  _UserRepository({
    required ProfileDao profileDao,
    required ArweaveService arweave,
    required ArioSDK arioSDK,
  })  : _profileDao = profileDao,
        _arweave = arweave,
        _arioSDK = arioSDK;

  // TODO: Check ProfileDAO to implement only one source for user data

  // Will return null if no user is not logged in - i.e. not present in the DB
  @override
  Future<User?> getUser(String password) async {
    final profile = await _profileDao.getDefaultProfile();

    if (profile == null) {
      logger.i('No profile found');
      return null;
    }

    final profileDetails = await _profileDao.loadDefaultProfile(password);
    final walletAddress = await profileDetails.wallet.getAddress();

    final user = User(
      profileType: ProfileType.values[profileDetails.details.profileType],
      wallet: profileDetails.wallet,
      cipherKey: profileDetails.key,
      password: password,
      walletAddress: walletAddress,
      walletBalance: await _getWalletBalanceSafely(walletAddress),
      errorFetchingIOTokens: false,
      sourceWalletAddress: profileDetails.details.sourceWalletAddress,
    );

    logger.d('Loaded user');

    return user;
  }

  /// Fetching the balance at login is best-effort: unlocking a locally stored
  /// profile must not fail or hang because the balance endpoint is
  /// unavailable. On error or timeout we fall back to zero and ArDriveAuth
  /// refreshes the balance asynchronously right after login.
  Future<BigInt> _getWalletBalanceSafely(String walletAddress) async {
    try {
      return await _arweave
          .getWalletBalance(walletAddress)
          .timeout(_walletBalanceLoginTimeout);
    } catch (e) {
      logger
          .w('Failed to fetch wallet balance during login, defaulting to 0: $e');
      return BigInt.zero;
    }
  }

  @override
  Future<void> saveUser(
    String password,
    ProfileType profileType,
    Wallet wallet, {
    String? sourceWalletAddress,
  }) async {
    logger.d('Saving user');

    await _profileDao.addProfile(
      // FIXME: This is a hack to get the username from the user object
      'user.username',
      password,
      wallet,
      profileType,
      sourceWalletAddress: sourceWalletAddress,
    );
  }

  @override
  Future<void> deleteUser() async {
    if (await hasUser()) {
      return _profileDao.deleteProfile();
    }
  }

  @override
  Future<bool> hasUser() async {
    final profile = await _profileDao.getDefaultProfile();

    return profile != null;
  }

  // Will return null if no user is logged in - i.e. not present in the DB
  @override
  Future<String?> getOwnerOfDefaultProfile() async {
    final profile = await _profileDao.getDefaultProfile();

    if (profile == null) {
      return null;
    }

    return profile.walletPublicKey;
  }

  @override
  Future<String?> getARIOTokens(Wallet wallet) async {
    String? arioTokens;

    if (isArioSDKSupportedOnPlatform()) {
      arioTokens = await _arioSDK.getARIOTokens(await wallet.getAddress());
      if (arioTokens == 'null') {
        throw Exception('Error fetching ARIOTokens');
      }
    }

    return arioTokens;
  }

  @override
  Future<BigInt> getBalance(Wallet wallet) async {
    final walletAddress = await wallet.getAddress();

    // Start both requests in parallel.
    final balanceFuture = _arweave.getWalletBalance(walletAddress);
    final pendingFeesFuture = _arweave.getPendingTxFees(walletAddress);

    // Always await the balance; if it fails, propagate the error.
    BigInt balance;
    try {
      balance = await balanceFuture;
    } catch (e) {
      logger.e('Failed to get wallet balance', e);

      // We can't do much without the wallet balance so rethrow
      rethrow;
    }

    // Try to subtract pending fees. On failure, fall back to balance only.
    try {
      final pending = await pendingFeesFuture;
      return balance - pending;
    } catch (e) {
      logger.w('Failed to get pending tx fees, using wallet balance only: $e');
      return balance;
    }
  }
}

class NoProfileFoundException implements Exception {
  final String message;

  NoProfileFoundException(this.message);
}
