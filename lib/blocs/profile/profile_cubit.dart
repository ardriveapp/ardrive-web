import 'dart:async';

import 'package:ardrive/entities/profile_source.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_state.dart';

/// [ProfileCubit] includes logic for managing the user's profile login status
/// and wallet balance.
class ProfileCubit extends Cubit<ProfileState> {
  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final ProfileDao _profileDao;
  final Database _db;
  final TabVisibilitySingleton _tabVisibilitySingleton;

  ProfileCubit({
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required ProfileDao profileDao,
    required Database db,
    required TabVisibilitySingleton tabVisibilitySingleton,
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _profileDao = profileDao,
        _db = db,
        _tabVisibilitySingleton = tabVisibilitySingleton,
        super(ProfileCheckingAvailability()) {
    promptToAuthenticate();
  }

  Future<bool> isCurrentProfileArConnect() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();
    if (profile != null) {
      return profile.profileType == ProfileType.arConnect.index;
    } else {
      return false;
    }
  }

  Future<void> promptToAuthenticate() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();
    final arconnect = ArConnectService();
    // Profile unavailable - route to new profile screen
    if (profile == null) {
      emit(ProfilePromptAdd());
      return;
    }
    // json wallet present - route to login screen
    if (profile.profileType != ProfileType.arConnect.index) {
      emit(ProfilePromptLogIn());
      return;
    }

    // ArConnect extension missing - route to profile screen
    if (!(arconnect.isExtensionPresent())) {
      emit(ProfilePromptAdd());
      return;
    }

    // ArConnect connected to expected wallet - route to login screen
    if (await arconnect.checkPermissions() &&
        profile.walletPublicKey == await arconnect.getPublicKey()) {
      emit(ProfilePromptLogIn());
      return;
    }

    // Unexpected ArConnect state - clean up and route to profile screen
    await _db.transaction(() async {
      for (final table in _db.allTables) {
        await _db.delete(table).go();
      }
    });
    emit(ProfilePromptAdd());
  }

  /// Returns true if detected wallet or permissions change
  Future<bool> checkIfWalletMismatch() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();
    final arconnect = ArConnectService();

    if (profile == null) {
      return false;
    }

    if (profile.profileType == ProfileType.arConnect.index) {
      try {
        if (!(await arconnect.checkPermissions())) {
          logger.i('ArConnect permissions changed');
          throw Exception('ArConnect permissions changed');
        }

        final currentPublicKey = await arconnect.getPublicKey();
        final savedPublicKey = profile.walletPublicKey;
        if (currentPublicKey != savedPublicKey) {
          return true;
        }
      } catch (e) {
        if (_tabVisibilitySingleton.isTabFocused()) {
          return false;
        }

        logger.e('Error checking ArConnect permissions', e);

        bool isWalletMismatch = false;

        await _tabVisibilitySingleton.onTabGetsFocusedFuture(() async {
          isWalletMismatch = await checkIfWalletMismatch();
        });

        return isWalletMismatch;
      }
    }

    return false;
  }

  /// Returns true if a logout flow is initiated as a result of a detected wallet or permissions change
  Future<bool> logoutIfWalletMismatch() async {
    final isMismatch = await checkIfWalletMismatch();
    if (isMismatch) {
      await logoutProfile();
    }
    return isMismatch;
  }

  Future<void> unlockDefaultProfile(
    String password,
    ProfileType profileType,
  ) async {
    emit(ProfileLoggingIn());

    final profile = await _profileDao.loadDefaultProfile(password);
    final arconnect = ArConnectService();

    final walletAddress = await (profileType == ProfileType.arConnect
        ? arconnect.getWalletAddress()
        : profile.wallet.getAddress());
    final walletBalance = await _arweave.getWalletBalance(walletAddress);
    final wallet = () {
      switch (profileType) {
        case ProfileType.json:
          return profile.wallet;
        case ProfileType.arConnect:
          return ArConnectWallet(arconnect);
      }
    }();

    final profileSource = ProfileSource(
      type: ProfileSourceType.values[profile.details.profileSourceType ?? 0],
      address: profile.details.profileSourceAddress,
    );

    emit(
      ProfileLoggedIn(
        username: profile.details.username,
        password: password,
        wallet: wallet,
        walletAddress: walletAddress,
        profileSource: profileSource,
        walletBalance: walletBalance,
        cipherKey: profile.key,
        useTurbo: _turboUploadService.useTurboUpload,
      ),
    );
  }

  Future<void> refreshBalance() async {
    final profile = state as ProfileLoggedIn;

    final walletAddress = await profile.wallet.getAddress();
    final walletBalance = await Future.wait([
      _arweave.getWalletBalance(walletAddress),
      _arweave.getPendingTxFees(walletAddress),
    ]).then((res) => res[0] - res[1]);

    emit(profile.copyWith(walletBalance: walletBalance));
  }

  Future<void> logoutProfile() async {
    logger.i('Logging out profile. state: ${state.runtimeType}');
    if (state is ProfileLoggingOut) {
      emit(ProfilePromptAdd());

      logger
          .i('Profile logout already in progress. state: ${state.runtimeType}');
      return;
    }

    emit(ProfileLoggingOut());
  }

  Future<void> deleteTables() async {
    // Delete all table data.
    await _db.transaction(() async {
      for (final table in _db.allTables) {
        await _db.delete(table).go();
      }
    });
  }
}
