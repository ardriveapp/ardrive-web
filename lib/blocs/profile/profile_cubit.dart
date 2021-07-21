import 'dart:async';

import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart' as arconnect;
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';

part 'profile_state.dart';

/// [ProfileCubit] includes logic for managing the user's profile login status
/// and wallet balance.
class ProfileCubit extends Cubit<ProfileState> {
  final ArweaveService _arweave;
  final ProfileDao _profileDao;
  final Database _db;

  ProfileCubit({
    @required ArweaveService arweave,
    @required ProfileDao profileDao,
    @required Database db,
  })  : _arweave = arweave,
        _profileDao = profileDao,
        _db = db,
        super(ProfileCheckingAvailability()) {
    promptToAuthenticate();
  }

  Future<bool> isCurrentProfileArConnect() async {
    return (await _profileDao.defaultProfile().getSingleOrNull()).profileType ==
        ProfileType.ArConnect.index;
  }

  Future<void> promptToAuthenticate() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();

    // Profile unavailable - route to new profile screen
    if (profile == null) {
      emit(ProfilePromptAdd());
      return;
    }

    // json wallet present - route to login screen
    if (profile.profileType != ProfileType.ArConnect.index) {
      emit(ProfilePromptLogIn());
      return;
    }

    // ArConnect extension missing - route to profile screen
    if (!(await arconnect.isExtensionPresent())) {
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
    if (profile == null) {
      return true;
    }

    if (profile.profileType == ProfileType.ArConnect.index) {
      if (!(await arconnect.checkPermissions())) {
        return true;
      }
      final currentPublicKey = await arconnect.getPublicKey();
      final savedPublicKey = profile.walletPublicKey;
      if (currentPublicKey != savedPublicKey) {
        return true;
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

    if (profile == null) {
      emit(ProfilePromptAdd());
      return;
    }

    final walletAddress = await (profileType == ProfileType.ArConnect
        ? arconnect.getWalletAddress()
        : profile.wallet.getAddress());
    final walletBalance = await _arweave.getWalletBalance(walletAddress);

    emit(
      ProfileLoggedIn(
        username: profile.details.username,
        password: password,
        wallet: profileType == ProfileType.ArConnect ? null : profile.wallet,
        walletAddress: walletAddress,
        walletBalance: walletBalance,
        cipherKey: profile.key,
      ),
    );
  }

  Future<void> refreshBalance() async {
    final profile = state as ProfileLoggedIn;

    final walletAddress = await profile.getWalletAddress();
    final walletBalance = await Future.wait([
      _arweave.getWalletBalance(walletAddress),
      _arweave.getPendingTxFees(walletAddress),
    ]).then((res) => res[0] - res[1]);

    emit(profile.copyWith(walletBalance: walletBalance));
  }

  /// Removes the user's existing profile and its associated data then prompts them to add another.
  ///
  /// Works even when the user is not authenticated.
  Future<void> logoutProfile() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();
    if (profile != null && profile.profileType == ProfileType.ArConnect.index) {
      try {
        await arconnect.disconnect();
      } catch (e) {
        print(e);
      }
    }

    emit(ProfileLoggingOut());

    // Delete all table data.
    await _db.transaction(() async {
      for (final table in _db.allTables) {
        await _db.delete(table).go();
      }
    });

    unawaited(promptToAuthenticate());
  }
}
