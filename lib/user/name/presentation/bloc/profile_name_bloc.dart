import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/ethereum/ethereum_name_service.dart';
import 'package:ardrive/services/solana/solana_name_service.dart';
import 'package:ardrive/user/name/domain/repository/profile_logo_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_name_event.dart';
part 'profile_name_state.dart';

class ProfileNameBloc extends Bloc<ProfileNameEvent, ProfileNameState> {
  // ignore: unused_field
  final ARNSRepository _arnsRepository; // kept for ArNS Solana integration
  // ignore: unused_field
  final ProfileLogoRepository _profileLogoRepository; // kept for ArNS Solana integration
  final ArDriveAuth _auth;
  final SolanaNameService _solanaNameService;
  final EthereumNameService _ethereumNameService;

  ProfileNameBloc(
    this._arnsRepository,
    this._profileLogoRepository,
    this._auth, {
    SolanaNameService? solanaNameService,
    EthereumNameService? ethereumNameService,
  })  : _solanaNameService = solanaNameService ?? SolanaNameService(),
        _ethereumNameService = ethereumNameService ?? EthereumNameService(),
        super(const ProfileNameInitial(null)) {
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
      /// if we are not refreshing, we emit a loading state
      if (!refreshName) {
        emit(ProfileNameLoading(walletAddress));
      }

      // Name service results are cached for the session.
      // Page reload clears the cache for fresh resolution.
      // Resolve cross-chain names: determine source address from either
      // the logged-in user or the walletAddress parameter itself (pre-login).
      final sourceAddress = isUserLoggedIn
          ? _auth.currentUser.sourceWalletAddress
          : (walletAddress.startsWith('0x') ? walletAddress : null);
      // For pre-login Solana: Solana addresses are base58, 32-44 chars,
      // don't start with 0x, and aren't 43-char base64url (Arweave).
      final isSolanaPreLogin = !isUserLoggedIn &&
          !walletAddress.startsWith('0x') &&
          walletAddress.length >= 32 &&
          walletAddress.length <= 44 &&
          !walletAddress.contains('-') &&
          !walletAddress.contains('_');

      final resolveAddress =
          sourceAddress ?? (isSolanaPreLogin ? walletAddress : null);

      if (resolveAddress != null) {
        if (resolveAddress.startsWith('0x')) {
          final ensProfile =
              await _ethereumNameService.getProfile(resolveAddress);
          if (ensProfile != null) {
            emit(ProfileNameLoaded(
              PrimaryNameDetails(
                primaryName: ensProfile.domain,
                logo: ensProfile.avatarUrl,
              ),
              walletAddress,
            ));
            return;
          }
        } else {
          final solProfile =
              await _solanaNameService.getProfile(resolveAddress);
          if (solProfile != null) {
            emit(ProfileNameLoaded(
              PrimaryNameDetails(
                primaryName: solProfile.domain,
                logo: solProfile.pictureUrl,
              ),
              walletAddress,
            ));
            return;
          }
        }
      }

      // ar.io primary names are now Solana-native and require a Solana
      // address. Skip the lookup since we only have the Arweave address here.
      // This will be re-enabled when ArNS Solana integration is complete.
      emit(ProfileNameLoadedWithWalletAddress(walletAddress));
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
