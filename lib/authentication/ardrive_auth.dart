import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/crypto/keys.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:arweave/arweave.dart';

abstract class ArDriveAuth {
  Future<bool> isUserLoggedIn();
  Future<bool> isExistingUser(Wallet wallet);
  Future<User> addUser(Wallet wallet, String password, ProfileType profileType);
  Future<User> login(Wallet wallet, String password);
  Future<User> unlockUser({required String password});
  Future<void> logout();
  User? get currentUser;
  Stream<User?> onAuthStateChanged();

  factory ArDriveAuth({
    required ArweaveService arweave,
    required UserRepository userRepository,
  }) =>
      _ArDriveAuth(arweave: arweave, userRepository: userRepository);
}

class _ArDriveAuth implements ArDriveAuth {
  _ArDriveAuth({
    required ArweaveService arweave,
    required UserRepository userRepository,
  })  : _arweave = arweave,
        _userService = userRepository;

  final UserRepository _userService;
  final ArweaveService _arweave;

  User? _currentUser;

  // getters and setters
  @override
  User get currentUser {
    if (_currentUser == null) {
      throw Exception('No user is currently logged in.');
    }

    return _currentUser!;
  }

  set currentUser(User? val) {
    if (_currentUser != val) {
      _currentUser = val;
    }
  }

  final StreamController<User?> _userController =
      StreamController<User?>.broadcast();

  @override
  Future<bool> isUserLoggedIn() async {
    return await _userService.hasUser();
  }

  @override
  Future<bool> isExistingUser(Wallet wallet) async {
    final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: profileQueryMaxRetries,
    );

    return driveTxs.isNotEmpty;
  }

  @override
  Future<User> login(Wallet wallet, String password) async {
    final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: profileQueryMaxRetries,
    );

    final privateDriveTxs = driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private);

    // Try and decrypt one of the user's private drive entities to check if they are entering the
    // right password.
    if (privateDriveTxs.isNotEmpty) {
      final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId)!;

      final checkDriveKey = await deriveDriveKey(
        wallet,
        checkDriveId,
        password,
      );

      DriveEntity? privateDrive;

      try {
        privateDrive = await _arweave.getLatestDriveEntityWithId(
          checkDriveId,
          checkDriveKey,
          profileQueryMaxRetries,
        );
      } catch (e) {
        throw AuthenticationUnknownException('Unknown error: $e');
      }

      if (privateDrive == null) {
        throw AuthenticationFailedException('Incorrect password');
      }
    }

    await _userService.deleteUser();

    // save user
    await _userService.saveUser(
      password,
      ProfileType.json,
      wallet,
    );

    currentUser = await _userService.getUser(password);

    _userController.add(_currentUser);

    return currentUser;
  }

  @override
  Future<User> addUser(
    Wallet wallet,
    String password,
    ProfileType profileType,
  ) async {
    // delete previous user
    // verify if it is necessary, the user only will add a new user if he is not logged in
    if (await _userService.hasUser()) {
      await _userService.deleteUser();
    }

    // save user
    await _userService.saveUser(
      password,
      profileType,
      wallet,
    );

    currentUser = await _userService.getUser(password);

    _userController.add(_currentUser);

    return currentUser;
  }

  @override
  Future<User> unlockUser({required String password}) async {
    try {
      currentUser = await _userService.getUser(password);

      _userController.add(_currentUser);

      return currentUser;
    } catch (e) {
      throw AuthenticationFailedException('Incorrect password.');
    }
  }

  @override
  Future<void> logout() async {
    currentUser = null;

    _userController.add(null);

    await _userService.deleteUser();
  }

  @override
  Stream<User?> onAuthStateChanged() => _userController.stream;
}

class AuthenticationFailedException implements Exception {
  final String message;

  AuthenticationFailedException(this.message);
}

class WalletMismatchException implements Exception {
  const WalletMismatchException();
}

class AuthenticationUnknownException implements Exception {
  final String message;

  AuthenticationUnknownException(this.message);
}
