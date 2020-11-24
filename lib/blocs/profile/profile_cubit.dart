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
        super(ProfileUnavailable()) {
    promptToAuthenticate();
  }

  Future<void> promptToAuthenticate() async {
    final profile = await _profileDao.selectDefaultProfile().getSingle();
    emit(profile != null ? ProfilePromptUnlock() : ProfilePromptAdd());
  }

  Future<void> unlockDefaultProfile(String password) async {
    emit(ProfileLoading());

    final profile = await _profileDao.loadDefaultProfile(password);

    if (profile != null) {
      final walletBalance =
          await _arweave.client.wallets.getBalance(profile.wallet.address);

      emit(
        ProfileLoaded(
          username: profile.details.username,
          password: password,
          wallet: profile.wallet,
          walletBalance: walletBalance,
          cipherKey: profile.key,
        ),
      );
    } else {
      emit(ProfileUnavailable());
    }
  }

  Future<void> refreshBalance() async {
    final state = this.state as ProfileLoaded;
    final walletBalance =
        await _arweave.client.wallets.getBalance(state.wallet.address);

    emit(state.copyWith(walletBalance: walletBalance));
  }

  /// Removes the user's existing profile and its associated data then prompts them to add another.
  ///
  /// Works even when the user is not authenticated.
  Future<void> logoutProfile() async {
    emit(ProfileLogoutInProgress());

    await _db.delete(_db.profiles).go();
    await _db.delete(_db.drives).go();
    await _db.delete(_db.folderEntries).go();
    await _db.delete(_db.fileEntries).go();

    unawaited(promptToAuthenticate());
  }
}
