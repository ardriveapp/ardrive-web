import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components/profile_auth_add_screen.dart';
import 'components/profile_auth_loading_screen.dart';
import 'components/profile_auth_onboarding_screen.dart';
import 'components/profile_auth_prompt_wallet_screen.dart';
import 'components/profile_auth_unlock_screen.dart';

class ProfileAuthPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state is ProfilePromptAdd) {
            return BlocProvider<ProfileAddCubit>(
              create: (context) => ProfileAddCubit(
                profileCubit: context.read<ProfileCubit>(),
                profileDao: context.read<ProfileDao>(),
                arweave: context.read<ArweaveService>(),
              ),
              child: BlocBuilder<ProfileAddCubit, ProfileAddState>(
                  builder: (context, state) {
                if (state is ProfileAddPromptWallet) {
                  return ProfileAuthPromptWalletScreen();
                } else if (state is ProfileAddOnboardingNewUser) {
                  return ProfileAuthOnboarding();
                } else if (state is ProfileAddPromptDetails) {
                  return ProfileAuthAddScreen();
                } else if (state is ProfileAddUserStateLoadInProgress ||
                    state is ProfileAddInProgress) {
                  return ProfileAuthLoadingScreen();
                }

                return const SizedBox();
              }),
            );
          } else if (state is ProfilePromptLogIn) {
            return ProfileAuthUnlockScreen();
          } else {
            return ProfileAuthLoadingScreen();
          }
        },
      );
}
