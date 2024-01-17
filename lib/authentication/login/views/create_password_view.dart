import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';
import 'forget_wallet.dart';

class CreatePasswordView extends StatefulWidget {
  const CreatePasswordView({super.key, required this.wallet});

  final Wallet wallet;

  @override
  State<CreatePasswordView> createState() => _CreatePasswordViewState();
}

class _CreatePasswordViewState extends State<CreatePasswordView> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<ArDriveFormState>();

  bool _isTermsChecked = false;

  bool _passwordIsValid = false;
  bool _confirmPasswordIsValid = false;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createAndConfirmPasswordPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: LoginCard(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => const SizedBox.shrink(),
                mobile: (context) => ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              Text(
                appLocalizationsOf(context).createAndConfirmPassword,
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline.headline5Regular(),
              ),
              const SizedBox(height: 16),
              Text(
                appLocalizationsOf(context)
                    .yourPasswordCannotBeCahngedOrRetrivied,
                style: ArDriveTypography.body.captionBold(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _createPasswordForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createPasswordForm() {
    return ArDriveForm(
      key: _formKey,
      child: Column(
        children: [
          ArDriveTextField(
            autofocus: true,
            controller: _passwordController,
            showObfuscationToggle: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            hintText: appLocalizationsOf(context).enterPassword,
            onChanged: (s) {
              _formKey.currentState?.validate();
            },
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.isEmpty) {
                setState(() {
                  _passwordIsValid = false;
                });
                return appLocalizationsOf(context).validationRequired;
              }

              setState(() {
                _passwordIsValid = true;
              });

              return null;
            },
          ),
          const SizedBox(height: 16),
          ArDriveTextField(
            controller: _confirmPasswordController,
            showObfuscationToggle: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            hintText: appLocalizationsOf(context).confirmPassword,
            textInputAction: TextInputAction.done,
            validator: (value) {
              if (value == null || value.isEmpty) {
                setState(() {
                  _confirmPasswordIsValid = false;
                });
                return appLocalizationsOf(context).validationRequired;
              } else if (value != _passwordController.text) {
                setState(() {
                  _confirmPasswordIsValid = false;
                });
                return appLocalizationsOf(context).passwordMismatch;
              }
              setState(() {
                _confirmPasswordIsValid = true;
              });

              return null;
            },
            onFieldSubmitted: (_) {
              if (_passwordIsValid &&
                  _confirmPasswordIsValid &&
                  _isTermsChecked) {
                _onSubmit();
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ArDriveCheckBox(
                title: '',
                checked: _isTermsChecked,
                onChange: ((value) {
                  setState(() => _isTermsChecked = value);
                }),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () => openUrl(
                    url: Resources.agreementLink,
                  ),
                  child: ArDriveClickArea(
                    child: Text.rich(
                      TextSpan(
                        children:
                            splitTranslationsWithMultipleStyles<InlineSpan>(
                          originalText:
                              appLocalizationsOf(context).aggreeToTerms_body,
                          defaultMapper: (text) => TextSpan(text: text),
                          parts: {
                            appLocalizationsOf(context).aggreeToTerms_link:
                                (text) => TextSpan(
                                      text: text,
                                      style: const TextStyle(
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              isDisabled: !_isTermsChecked ||
                  _passwordIsValid == false ||
                  _confirmPasswordIsValid == false,
              onPressed: _onSubmit,
              text: appLocalizationsOf(context).proceed,
            ),
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
    );
  }

  void _onSubmit() {
    final isValid = _formKey.currentState!.validateSync();

    if (!isValid) {
      showArDriveDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.triangle(
              size: 88,
              color: ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
            ),
            title: appLocalizationsOf(context).passwordCannotBeEmpty,
            content: appLocalizationsOf(context).pleaseTryAgain,
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              )
            ],
          ));
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      showArDriveDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.triangle(
              size: 88,
              color: ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
            ),
            title: appLocalizationsOf(context).passwordDoNotMatch,
            content: appLocalizationsOf(context).pleaseTryAgain,
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              )
            ],
          ));
      return;
    }

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createdAndConfirmedPassword,
    );

    context.read<LoginBloc>().add(
          CreatePassword(
            password: _passwordController.text,
            wallet: widget.wallet,
          ),
        );
  }
}
