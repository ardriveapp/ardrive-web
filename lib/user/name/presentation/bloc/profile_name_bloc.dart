import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_name_event.dart';
part 'profile_name_state.dart';

class ProfileNameBloc extends Bloc<ProfileNameEvent, ProfileNameState> {
  final ARNSRepository _arnsRepository;
  final ArDriveAuth _auth;

  ProfileNameBloc(this._arnsRepository, this._auth)
      : super(ProfileNameInitial(_auth.currentUser.walletAddress)) {
    on<ProfileNameEvent>((event, emit) async {
      try {
        logger.d(
            'Loading primary name for address: ${_auth.currentUser.walletAddress}');

        // loads primary name for the wallet
        emit(ProfileNameLoading(_auth.currentUser.walletAddress));

        final primaryName = await _arnsRepository.getPrimaryName(
          _auth.currentUser.walletAddress,
        );

        logger.d('Primary Name Loaded: $primaryName');

        // we only show the first 7 characters of the primary name
        // if the primary name is longer than 7 characters
        final truncatedPrimaryName =
            primaryName.length > 7 ? primaryName.substring(0, 7) : primaryName;

        emit(ProfileNameLoaded(
            truncatedPrimaryName, _auth.currentUser.walletAddress));
      } catch (e) {
        logger.e('Error getting primary name.', e);
        emit(ProfileNameLoadedWithWalletAddress(
          _auth.currentUser.walletAddress,
        ));
      }
    });
  }
}
