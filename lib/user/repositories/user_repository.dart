import 'package:ardrive/entities/profile_source.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';

abstract class UserRepository {
  Future<bool> hasUser();
  Future<User?> getUser(String password);
  Future<void> saveUser(
    String password,
    ProfileType profileType,
    ProfileSource profileSource,
    Wallet wallet,
  );
  Future<void> deleteUser();

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
  @override
  Future<User?> getUser(String password) async {
    final profile = await _profileDao.getDefaultProfile();

    if (profile == null) {
      return null;
    }

    final profileDetails = await _profileDao.loadDefaultProfile(password);

    final user = User(
      profileType: ProfileType.values[profileDetails.details.profileType],
      profileSource: ProfileSource(
        type:
            ProfileSourceType.values[profileDetails.details.profileSourceType],
        address: profileDetails.details.walletPublicKey,
      ),
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
  Future<void> saveUser(String password, ProfileType profileType,
      ProfileSource profileSource, Wallet wallet) async {
    logger.d('Saving user');

    await _profileDao.addProfile(
      // FIXME: This is a hack to get the username from the user object
      'user.username',
      password,
      wallet,
      profileType,
      profileSource,
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
}

class NoProfileFoundException implements Exception {
  final String message;

  NoProfileFoundException(this.message);
}
