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
        refreshName: false,
        refreshLogo: false,
        emit: emit,
      );
    });
    on<RefreshProfileName>((event, emit) async {
      await _loadProfileName(
        walletAddress: _auth.currentUser.walletAddress,
        refreshName: true,
        refreshLogo: true,
        emit: emit,
      );
    });
    on<LoadProfileNameBeforeLogin>((event, emit) async {
      emit(ProfileNameLoading(event.walletAddress));

      await _loadProfileName(
        walletAddress: event.walletAddress,
        refreshName: true,
        refreshLogo: false,
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
    required bool refreshName,
    required bool refreshLogo,
    required Emitter<ProfileNameState> emit,
    bool isUserLoggedIn = true,
  }) async {
    try {
      String? profileLogoTxId;

      /// if we are not refreshing, we emit a loading state
      if (!refreshName) {
        emit(ProfileNameLoading(walletAddress));
      }

      if (!refreshLogo) {
        logger.d('Getting profile logo tx id from cache');

        profileLogoTxId =
            await _profileLogoRepository.getProfileLogoTxId(walletAddress);

        logger.d('Profile logo tx id: $profileLogoTxId');
      }

      final getLogo = refreshLogo || profileLogoTxId == null;

      logger.d('Getting primary name with getLogo: $getLogo');

      var primaryNameDetails = await _arnsRepository.getPrimaryName(
        walletAddress,
        update: refreshName,
        getLogo: getLogo,
      );

      if (!refreshLogo && profileLogoTxId != null) {
        primaryNameDetails = primaryNameDetails.copyWith(logo: profileLogoTxId);
      }

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
