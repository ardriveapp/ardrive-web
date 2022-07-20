import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/wallet_switch_dialog.dart';
import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/profile_auth/components/profile_auth_fail_screen.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components/profile_auth_add_screen.dart';
import 'components/profile_auth_loading_screen.dart';
import 'components/profile_auth_onboarding_screen.dart';
import 'components/profile_auth_prompt_wallet_screen.dart';
import 'components/profile_auth_unlock_screen.dart';

class ProfileAuthPage extends StatefulWidget {
  @override
  _ProfileAuthPageState createState() => _ProfileAuthPageState();
}

class _ProfileAuthPageState extends State<ProfileAuthPage> {
  bool _showWalletSwitchDialog = true;

  void listenForWalletSwitch() {
    onArConnectWalletSwitch(() {
      if (_showWalletSwitchDialog) {
        showDialog(
          context: context,
          builder: (context) => WalletSwitchDialog(
            fromAuthPage: true,
          ),
        );
      }
      //Used to prevent dialog from being shown multiple times
      _showWalletSwitchDialog = false;
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state is ProfilePromptAdd) {
            return BlocProvider<ProfileAddCubit>(
              create: (context) => ProfileAddCubit(
                profileCubit: context.read<ProfileCubit>(),
                profileDao: context.read<ProfileDao>(),
                arweave: context.read<ArweaveService>(),
                context: context,
              ),
              child: BlocBuilder<ProfileAddCubit, ProfileAddState>(
                  builder: (context, state) {
                if (state is ProfileAddPromptWallet ||
                    state is ProfileLoggingOut) {
                  return ProfileAuthPromptWalletScreen();
                } else if (state is ProfileAddOnboardingNewUser) {
                  listenForWalletSwitch();
                  return ProfileAuthOnboarding();
                } else if (state is ProfileAddPromptDetails) {
                  listenForWalletSwitch();
                  return ProfileAuthAddScreen();
                } else if (state is ProfileAddUserStateLoadInProgress ||
                    state is ProfileAddInProgress) {
                  return ProfileAuthLoadingScreen(
                    isArConnect:
                        (context.read<ProfileAddCubit>().getProfileType() ==
                            ProfileType.ArConnect),
                  );
                } else if (state is ProfileAddFailure) {
                  return ProfileAuthFailScreen();
                }

                return const SizedBox();
              }),
            );
          } else if (state is ProfilePromptLogIn) {
            listenForWalletSwitch();

            return ProfileAuthUnlockScreen();
          } else {
            return ProfileAuthLoadingScreen();
          }
        },
      );
}
