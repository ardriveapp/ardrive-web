import 'dart:async';

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

  Future<void> promptToAuthenticate() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();

    if (profile != null) {
      if (profile.encryptedWallet.isEmpty) {
        //Clear database in case of arconnect refresh
        if (arconnect.isExtensionPresent() &&
            !await arconnect.checkPermissions()) {
          await _db.transaction(() async {
            for (final table in _db.allTables) {
              await _db.delete(table).go();
            }
          });
          emit(ProfilePromptAdd());
          return;
        }
      } else {
        emit(ProfilePromptLogIn());
        return;
      }
    }
    emit(ProfilePromptAdd());
  }

  Future<void> unlockDefaultProfile(String password, bool isArconnect) async {
    emit(ProfileLoggingIn());

    final profile = await _profileDao.loadDefaultProfile(password);

    if (profile != null) {
      final walletAddress = await (profile.wallet == null
          ? arconnect.getWalletAddress()
          : profile.wallet.getAddress());
      final walletBalance = await _arweave.getWalletBalance(walletAddress);

      emit(
        ProfileLoggedIn(
          username: profile.details.username,
          password: password,
          wallet: isArconnect ? null : profile.wallet,
          walletAddress: walletAddress,
          walletBalance: walletBalance,
          cipherKey: profile.key,
        ),
      );
    } else {
      emit(ProfilePromptAdd());
    }
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
    try {
      await arconnect.disconnect();
    } catch (e) {
      print(e);
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
