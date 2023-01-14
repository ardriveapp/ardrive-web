import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/crypto/keys.dart';
import 'package:ardrive/user/services/user_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';

import '../entities/drive_entity.dart';
import '../entities/profile_types.dart';
import '../services/arweave/arweave_service.dart';

class ArDriveAuth extends ChangeNotifier {
  ArDriveAuth({
    required ArweaveService arweave,
    required UserService userService,
  })  : _arweave = arweave,
        _userService = userService;

  final UserService _userService;
  final ArweaveService _arweave;

  User? _user;

  Future<bool> isUserLoggedIn() async {
    return await _userService.isUserLoggedIn();
  }

  Future<bool> isExistingUser(Wallet wallet) async {
    return await _userService.isExistingUser(
      await wallet.getAddress(),
    );
  }

  Future<User> login(Wallet wallet, String password) async {
    debugPrint('Logging in...');

    final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: profileQueryMaxRetries,
    );

    debugPrint('driveTxs: $driveTxs');

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

    debugPrint('Saving user...');

    await _userService.deleteUser();

    // save user
    await _userService.saveUser(
      password,
      ProfileType.json,
      wallet,
    );

    return await _userService.getProfile(password);
  }

  Future<User> addUser(Wallet wallet, String password) async {
    // delete previous user
    // verify if it is necessary, the user only will add a new user if he is not logged in
    await _userService.deleteUser();

    // save user
    await _userService.saveUser(
      password,
      ProfileType.json,
      wallet,
    );

    return await _userService.getProfile(password);
  }

  Future<User> unlockUser({required String password}) async {
    try {
      final user = await _userService.getProfile(password);

      return user;
    } catch (e) {
      throw AuthenticationFailedException('Incorrect password');
    }
  }

  Future<void> logout() async {
    // TODO: delete profile
    await _userService.deleteUser();
  }

  // getters and setters
  User? get user => _user;

  set user(User? val) {
    if (_user != val) {
      _user = user;
    }
    notifyListeners();
  }
}

class AuthenticationFailedException implements Exception {
  final String message;

  AuthenticationFailedException(this.message);
}

class AuthenticationUnknownException implements Exception {
  final String message;

  AuthenticationUnknownException(this.message);
}
