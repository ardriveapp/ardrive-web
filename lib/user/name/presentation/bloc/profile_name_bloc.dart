import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/name/domain/repository/profile_logo_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_name_event.dart';
part 'profile_name_state.dart';

class ProfileNameBloc extends Bloc<ProfileNameEvent, ProfileNameState> {
  final ARNSRepository _arnsRepository;
  final ProfileLogoRepository _profileLogoRepository;
  final ArDriveAuth _auth;

  ProfileNameBloc(
    this._arnsRepository,
    this._profileLogoRepository,
    this._auth,
  ) : super(const ProfileNameInitial(null)) {
    on<LoadProfileName>((event, emit) async {
      await _loadProfileName(
        walletAddress: _auth.currentUser.walletAddress,
        refresh: false,
        emit: emit,
      );
    });
    on<RefreshProfileName>((event, emit) async {
      await _loadProfileName(
        walletAddress: _auth.currentUser.walletAddress,
        refresh: true,
        emit: emit,
      );
    });
    on<LoadProfileNameAnonymous>((event, emit) async {
      emit(ProfileNameLoading(event.walletAddress));

      logger
          .d('Loading profile name for anonymous user ${event.walletAddress}');

      await _loadProfileName(
        walletAddress: event.walletAddress,
        refresh: true,
        emit: emit,
        isUserLoggedIn: false,
      );
    });
    on<CleanProfileName>((event, emit) {
      emit(const ProfileNameInitial(null));
    });
  }

  Future<void> _loadProfileName({
    required String walletAddress,
    required bool refresh,
    required Emitter<ProfileNameState> emit,
    bool isUserLoggedIn = true,
  }) async {
    try {
      String? profileLogoTxId;

      /// if we are not refreshing, we emit a loading state
      if (!refresh) {
        emit(ProfileNameLoading(walletAddress));
      }

      if (refresh && !isUserLoggedIn) {
        profileLogoTxId =
            await _profileLogoRepository.getProfileLogoTxId(walletAddress);
      }

      var primaryNameDetails = await _arnsRepository.getPrimaryName(
        walletAddress,
        update: refresh,
        getLogo: profileLogoTxId == null,
      );

      primaryNameDetails = primaryNameDetails.copyWith(
        logo: profileLogoTxId == null ? primaryNameDetails.logo : null,
      );

      if (isUserLoggedIn && _auth.currentUser.walletAddress != walletAddress) {
        // A user can load profile name and log out while fetching this request. Then log in again. We should not emit a profile name loaded state in this case.
        logger.d('User logged out while fetching profile name');

        return;
      }

      if (profileLogoTxId == null && primaryNameDetails.logo != null) {
        _profileLogoRepository.setProfileLogoTxId(
          walletAddress,
          primaryNameDetails.logo!,
        );
      }

      emit(ProfileNameLoaded(primaryNameDetails, walletAddress));
    } catch (e) {
      if (e is PrimaryNameNotFoundException) {
        logger.d('Primary name not found for address: $walletAddress');
      } else {
        logger.e('Error getting primary name.', e);
      }

      emit(
        ProfileNameLoadedWithWalletAddress(
          walletAddress,
        ),
      );
    }
  }
}
