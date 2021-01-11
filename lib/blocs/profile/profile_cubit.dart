import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
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

  Future<void> promptToAuthenticate() async {
    final profile = await _profileDao.defaultProfile().getSingle();
    emit(profile != null ? ProfilePromptLogIn() : ProfilePromptAdd());
  }

  Future<void> unlockDefaultProfile(String password) async {
    emit(ProfileLoggingIn());

    final profile = await _profileDao.loadDefaultProfile(password);

    if (profile != null) {
      final walletBalance =
          await _arweave.client.wallets.getBalance(profile.wallet.address);

      emit(
        ProfileLoggedIn(
          username: profile.details.username,
          password: password,
          wallet: profile.wallet,
          walletBalance: walletBalance,
          cipherKey: profile.key,
        ),
      );
    } else {
      emit(ProfilePromptAdd());
    }
  }

  Future<void> refreshBalance() async {
    final state = this.state as ProfileLoggedIn;
    final walletBalance =
        await _arweave.client.wallets.getBalance(state.wallet.address);

    emit(state.copyWith(walletBalance: walletBalance));
  }

  /// Removes the user's existing profile and its associated data then prompts them to add another.
  ///
  /// Works even when the user is not authenticated.
  Future<void> logoutProfile() async {
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
