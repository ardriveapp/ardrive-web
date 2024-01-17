import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/components/biometric_toggle.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/forget_wallet.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../components/truncated_address.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';

class PromptPasswordView extends StatefulWidget {
  const PromptPasswordView({super.key, this.wallet});

  final Wallet? wallet;

  @override
  State<PromptPasswordView> createState() => _PromptPasswordViewState();
}

class _PromptPasswordViewState extends State<PromptPasswordView> {
  final _passwordController = TextEditingController();
  bool _isPasswordValid = false;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.welcomeBackPage);
  }

  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      child: LoginCard(
        content: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                appLocalizationsOf(context).welcomeBackEmphasized,
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline.headline4Bold(),
              ),
              _buildAddressPreview(
                context,
                maybeWallet: widget.wallet,
              ),
              Column(
                children: [
                  ArDriveTextField(
                      showObfuscationToggle: true,
                      controller: _passwordController,
                      obscureText: true,
                      autofocus: true,
                      autofillHints: const [AutofillHints.password],
                      hintText: appLocalizationsOf(context).enterPassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          setState(() {
                            _isPasswordValid = false;
                          });
                          return appLocalizationsOf(context).validationRequired;
                        }

                        setState(() {
                          _isPasswordValid = true;
                        });

                        return null;
                      },
                      onFieldSubmitted: (_) async {
                        if (_isPasswordValid) {
                          _onSubmit();
                        }
                      }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ArDriveButton(
                      isDisabled: !_isPasswordValid,
                      onPressed: () {
                        _onSubmit();
                      },
                      text: appLocalizationsOf(context).proceed,
                    ),
                  ),
                  const SizedBox(height: 16),
                  BiometricToggle(
                    onEnableBiometric: () {
                      context
                          .read<LoginBloc>()
                          .add(const UnLockWithBiometrics());
                    },
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ArDriveButton(
                  onPressed: () {
                    forgetWallet(context);
                  },
                  style: ArDriveButtonStyle.tertiary,
                  text: appLocalizationsOf(context).forgetWallet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSubmit() {
    if (widget.wallet == null) {
      context.read<LoginBloc>().add(
            UnlockUserWithPassword(
              password: _passwordController.text,
            ),
          );
    } else {
      context.read<LoginBloc>().add(
            LoginWithPassword(
              password: _passwordController.text,
              wallet: widget.wallet!,
            ),
          );
    }
  }
}

Widget _buildAddressPreview(
  BuildContext context, {
  required Wallet? maybeWallet,
}) {
  Future<String?> getWalletAddress() async {
    if (maybeWallet == null) {
      return context.read<ArDriveAuth>().getWalletAddress();
    }
    return maybeWallet.getAddress();
  }

  return FutureBuilder(
    future: getWalletAddress(),
    builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
      if (snapshot.hasData) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              appLocalizationsOf(context).walletAddress,
              style: ArDriveTypography.body
                  .captionRegular()
                  .copyWith(fontSize: 18),
            ),
            const SizedBox(width: 8),
            TruncatedAddress(
              walletAddress: snapshot.data!,
              fontSize: 18,
            ),
          ],
        );
      } else {
        return const SizedBox.shrink();
      }
    },
  );
}
