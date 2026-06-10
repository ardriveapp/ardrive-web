import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/ethereum/ethereum_name_service.dart';
import 'package:ardrive/services/solana/solana_name_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_name_event.dart';
part 'profile_name_state.dart';

class ProfileNameBloc extends Bloc<ProfileNameEvent, ProfileNameState> {
  final ArDriveAuth _auth;
  final SolanaNameService _solanaNameService;
  final EthereumNameService _ethereumNameService;

  ProfileNameBloc(
    this._auth, {
    SolanaNameService? solanaNameService,
    EthereumNameService? ethereumNameService,
  })  : _solanaNameService = solanaNameService ?? SolanaNameService(),
        _ethereumNameService = ethereumNameService ?? EthereumNameService(),
        super(const ProfileNameInitial(null)) {
    on<LoadProfileName>((event, emit) async {
      await _loadProfileName(
        walletAddress: _auth.currentUser.walletAddress,
        emit: emit,
      );
    });
    on<RefreshProfileName>((event, emit) async {
      _solanaNameService.clearCache();
      _ethereumNameService.clearCache();
      await _loadProfileName(
        walletAddress: _auth.currentUser.walletAddress,
        emit: emit,
      );
    });
    on<LoadProfileNameBeforeLogin>((event, emit) async {
      await _loadProfileName(
        walletAddress: event.walletAddress,
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
    required Emitter<ProfileNameState> emit,
    bool isUserLoggedIn = true,
  }) async {
    try {
      emit(ProfileNameLoading(walletAddress));

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

      // No ArNS/AO primary name resolution — only .sol/.eth above.
      // Fall through to truncated wallet address.
      emit(ProfileNameLoadedWithWalletAddress(walletAddress));
    } catch (e) {
      logger.e('Error resolving profile name', e);
      emit(ProfileNameLoadedWithWalletAddress(walletAddress));
    }
  }
}
