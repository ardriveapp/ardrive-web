import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_name_event.dart';
part 'profile_name_state.dart';

class ProfileNameBloc extends Bloc<ProfileNameEvent, ProfileNameState> {
  final ARNSRepository _arnsRepository;
  final ArDriveAuth _auth;

  ProfileNameBloc(this._arnsRepository, this._auth)
      : super(ProfileNameInitial(_auth.currentUser.walletAddress)) {
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
  }

  Future<void> _loadProfileName({
    required String walletAddress,
    required bool refresh,
    required Emitter<ProfileNameState> emit,
  }) async {
    try {
      /// if we are not refreshing, we emit a loading state
      if (!refresh) {
        emit(ProfileNameLoading(walletAddress));
      }

      final primaryName =
          await _arnsRepository.getPrimaryName(walletAddress, update: refresh);

      emit(ProfileNameLoaded(primaryName, walletAddress));
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
