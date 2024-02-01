import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';

abstract class UserRepository {
  Future<bool> hasUser();
  Future<User?> getUser(String password);
  Future<void> saveUser(
    String password,
    ProfileType profileType,
    Wallet wallet,
  );
  Future<void> deleteUser();
  Future<String?> getOwnerOfDefaultProfile();

  factory UserRepository(ProfileDao profileDao, ArweaveService arweave) =>
      _UserRepository(
        profileDao: profileDao,
        arweave: arweave,
      );
}

class _UserRepository implements UserRepository {
  final ProfileDao _profileDao;
  final ArweaveService _arweave;

  _UserRepository({
    required ProfileDao profileDao,
    required ArweaveService arweave,
  })  : _profileDao = profileDao,
        _arweave = arweave;

  // TODO: Check ProfileDAO to implement only one source for user data

  // Will return null if no user is not logged in - i.e. not present in the DB
  @override
  Future<User?> getUser(String password) async {
    final profile = await _profileDao.getDefaultProfile();

    if (profile == null) {
      return null;
    }

    final profileDetails = await _profileDao.loadDefaultProfile(password);

    final user = User(
      profileType: ProfileType.values[profileDetails.details.profileType],
      wallet: profileDetails.wallet,
      cipherKey: profileDetails.key,
      password: password,
      walletAddress: await profileDetails.wallet.getAddress(),
      walletBalance: await _arweave.getWalletBalance(
        await profileDetails.wallet.getAddress(),
      ),
    );

    logger.d('Loaded user');

    return user;
  }

  @override
  Future<void> saveUser(
      String password, ProfileType profileType, Wallet wallet) async {
    logger.d('Saving user');

    await _profileDao.addProfile(
      // FIXME: This is a hack to get the username from the user object
      'user.username',
      password,
      wallet,
      profileType,
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
}

class NoProfileFoundException implements Exception {
  final String message;

  NoProfileFoundException(this.message);
}
