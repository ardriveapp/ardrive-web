import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/user.dart';
import 'package:arweave/arweave.dart';

abstract class UserService {
  Future<User> getProfile(String password);
  Future<bool> isUserLoggedIn();
  Future<bool> isExistingUser(String walletAddress);
  Future<void> saveUser(
      String password, ProfileType profileType, Wallet wallet);
  Future<void> deleteUser();

  factory UserService(ProfileDao profileDao, ArweaveService arweave) =>
      _UserService(
        profileDao: profileDao,
        arweave: arweave,
      );
}

class _UserService implements UserService {
  final ProfileDao _profileDao;
  final ArweaveService _arweave;

  // TODO(@thiagocarvalhodev): create a data source for this
  _UserService({
    required ProfileDao profileDao,
    required ArweaveService arweave,
  })  : _profileDao = profileDao,
        _arweave = arweave;

  @override
  Future<User> getProfile(String password) async {
    final profile = await _profileDao.loadDefaultProfile(password);

    // TODO: Handle this error in a better way
    if (profile == null) {
      throw NoProfileFoundException('No profile found');
    }

    return User(
      profileType: ProfileType.values[profile.details.profileType],
      wallet: profile.wallet,
      cipherKey: profile.key,
      password: password,
      walletAddress: await profile.wallet.getAddress(),
      walletBalance:
          await _arweave.getWalletBalance(await profile.wallet.getAddress()),
    );
  }

  @override
  Future<bool> isUserLoggedIn() async {
    final profile = await _profileDao.getDefaultProfile();

    return profile != null;
  }

  @override
  Future<bool> isExistingUser(String walletAddress) async {
    final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
      walletAddress,
      maxRetries: profileQueryMaxRetries,
    );

    return driveTxs.isNotEmpty;
  }

  @override
  Future<void> saveUser(
      String password, ProfileType profileType, Wallet wallet) async {
    await _profileDao.addProfile(
      // FIXME: This is a hack to get the username from the user object
      'user.username',
      password,
      wallet,
      profileType,
    );
  }

  @override
  Future<User> createUser(
      String password, ProfileType profileType, Wallet wallet) {
    // TODO: implement createUser
    throw UnimplementedError();
  }

  @override
  Future<void> deleteUser() async {
    _profileDao.deleteProfile();
  }
}

const profileQueryMaxRetries = 6;

class NoProfileFoundException implements Exception {
  final String message;

  NoProfileFoundException(this.message);
}
