import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final ArweaveService _arweave;
  final ProfileDao _profileDao;

  ProfileCubit({
    @required ArweaveService arweave,
    @required ProfileDao profileDao,
  })  : _arweave = arweave,
        _profileDao = profileDao,
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

  Future<void> signOut() async {
    emit(ProfileUnavailable());
    await promptToAuthenticate();
  }
}
