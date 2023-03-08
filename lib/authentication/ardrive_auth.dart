import 'dart:async';

import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';

import '../core/crypto/crypto.dart';

abstract class ArDriveAuth {
  Future<bool> isUserLoggedIn();
  Future<bool> isExistingUser(Wallet wallet);
  Future<User> login(Wallet wallet, String password, ProfileType profileType);
  Future<User> unlockUser({required String password});
  Future<void> logout();
  User? get currentUser;
  Stream<User?> onAuthStateChanged();

  factory ArDriveAuth({
    required ArweaveService arweave,
    required UserRepository userRepository,
    required ArDriveCrypto crypto,
  }) =>
      _ArDriveAuth(
        arweave: arweave,
        userRepository: userRepository,
        crypto: crypto,
      );
}

class _ArDriveAuth implements ArDriveAuth {
  _ArDriveAuth({
    required ArweaveService arweave,
    required UserRepository userRepository,
    required ArDriveCrypto crypto,
  })  : _arweave = arweave,
        _crypto = crypto,
        _userRepository = userRepository;

  final UserRepository _userRepository;
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;

  User? _currentUser;

  // getters and setters
  @override
  User get currentUser {
    if (_currentUser == null) {
      throw const AuthenticationUserIsNotLoggedInException();
    }

    return _currentUser!;
  }

  set currentUser(User? user) {
    _currentUser = user;
  }

  final StreamController<User?> _userStreamController =
      StreamController<User?>.broadcast();

  @override
  Future<bool> isUserLoggedIn() async {
    return await _userRepository.hasUser();
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
  Future<User> login(
      Wallet wallet, String password, ProfileType profileType) async {
    final isValidPassword = await _validateUser(
      wallet,
      password,
    );

    if (!isValidPassword) {
      throw AuthenticationFailedException('Incorrect password');
    }

    currentUser = await _addUser(wallet, password, profileType);

    _userStreamController.add(_currentUser);

    return currentUser;
  }

  Future<User> _addUser(
    Wallet wallet,
    String password,
    ProfileType profileType,
  ) async {
    await _saveUser(password, profileType, wallet);

    currentUser = await _userRepository.getUser(password);

    _userStreamController.add(_currentUser);

    return currentUser;
  }

  @override
  Future<User> unlockUser({required String password}) async {
    try {
      currentUser = await _userRepository.getUser(password);

      _userStreamController.add(_currentUser);

      return currentUser;
    } catch (e) {
      throw AuthenticationFailedException('Incorrect password.');
    }
  }

  @override
  Future<void> logout() async {
    currentUser = null;

    _userStreamController.add(null);

    await _userRepository.deleteUser();
  }

  @override
  Stream<User?> onAuthStateChanged() => _userStreamController.stream;

  Future<bool> _validateUser(
    Wallet wallet,
    String password,
  ) async {
    final firstDrivePrivateDriveTxId = await _arweave.getFirstPrivateDriveTxId(
      wallet,
      maxRetries: profileQueryMaxRetries,
    );

    // Try and decrypt one of the user's private drive entities to check if they are entering the
    // right password.
    if (firstDrivePrivateDriveTxId != null) {
      late SecretKey checkDriveKey;
      try {
        checkDriveKey = await _crypto.deriveDriveKey(
          wallet,
          firstDrivePrivateDriveTxId,
          password,
        );
      } catch (e) {
        throw AuthenticationFailedException('Wrong password');
      }

      final privateDrive = await _arweave.getLatestDriveEntityWithId(
        firstDrivePrivateDriveTxId,
        checkDriveKey,
        profileQueryMaxRetries,
      );

      return privateDrive != null;
    }

    return true;
  }

  Future<void> _saveUser(
    String password,
    ProfileType profileType,
    Wallet wallet,
  ) async {
    // delete previous user
    // verify if it is necessary, the user only will add a new user if he is not logged in
    if (await _userRepository.hasUser()) {
      await _userRepository.deleteUser();
    }

    // save user
    await _userRepository.saveUser(
      password,
      profileType,
      wallet,
    );
  }
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

class AuthenticationUserIsNotLoggedInException implements Exception {
  const AuthenticationUserIsNotLoggedInException();
}
