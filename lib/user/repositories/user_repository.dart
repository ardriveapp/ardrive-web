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
  /// How long login waits for the wallet balance before carrying on without it.
  static const _loginBalanceTimeout = Duration(seconds: 5);

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
      walletBalance: await _getLoginWalletBalance(walletAddress),
      errorFetchingIOTokens: false,
      sourceWalletAddress: profileDetails.details.sourceWalletAddress,
    );

    logger.d('Loaded user');

    return user;
  }

  /// The balance shown at login is best-effort. `getWalletBalance` has no
  /// deadline of its own, and unlocking a profile that is stored locally must
  /// not hang or fail because the balance endpoint does. On a timeout or an
  /// error this returns zero, the same value a wallet with no AR shows;
  /// `ArDriveAuth` refreshes the balance in the background right after login
  /// and publishes the real value through `onAuthStateChanged`.
  Future<BigInt> _getLoginWalletBalance(String walletAddress) async {
    try {
      return await _arweave
          .getWalletBalance(walletAddress)
          .timeout(_loginBalanceTimeout);
    } catch (e) {
      logger.w(
        'Could not fetch the wallet balance at login, showing zero until the '
        'background refresh: $e',
      );
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
