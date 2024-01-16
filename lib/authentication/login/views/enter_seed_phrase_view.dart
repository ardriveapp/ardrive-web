import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'login_card.dart';
import 'max_device_sizes_constrained_box.dart';

class EnterSeedPhraseView extends StatefulWidget {
  const EnterSeedPhraseView({super.key});

  @override
  State<EnterSeedPhraseView> createState() => _EnterSeedPhraseViewState();
}

class _EnterSeedPhraseViewState extends State<EnterSeedPhraseView> {
  final _seedPhraseController = ArDriveMultlineObscureTextController();
  final _formKey = GlobalKey<ArDriveFormState>();

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.enterSeedPhrasePage);
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
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  // TODO: create/update localization key
                  'Enter Seed Phrase',
                  style: ArDriveTypography.headline.headline4Regular(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                // TODO: create/update localization key
                'Please enter your 12 word seed phrase and separate each word with a space.',
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.smallBold(),
              ),
              const SizedBox(height: 50),
              _createSeedPhraseForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createSeedPhraseForm() {
    return ArDriveForm(
      key: _formKey,
      child: Column(
        children: [
          Align(
              alignment: Alignment.topLeft,
              child: Text(
                // TODO: create/update localization key
                'Seed Phrase',
                style:
                    ArDriveTypography.body.smallBold().copyWith(fontSize: 14),
              )),
          const SizedBox(height: 8),
          ArDriveTextField(
            autofocus: true,
            controller: _seedPhraseController,
            showObfuscationToggle: true,
            obscureText: true,
            // TODO: create/update localization key
            hintText: 'Enter Seed Phrase',
            textInputAction: TextInputAction.next,
            minLines: 3,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              onPressed: _onSubmit,
              // TODO: create/update localization key
              text: 'Continue',
              fontStyle:
                  ArDriveTypography.body.smallBold700(color: Colors.white),
            ),
          ),
          const SizedBox(height: 56),
          Align(
              alignment: Alignment.bottomLeft,
              child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      context.read<LoginBloc>().add(const ForgetWallet());
                    },
                    child: Row(children: [
                      ArDriveIcons.carretLeft(
                          size: 16,
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault),
                      Text(appLocalizationsOf(context).back),
                    ]),
                  ))),
        ],
      ),
    );
  }

  void _onSubmit() async {
    final isValid = _seedPhraseController.text.isNotEmpty &&
        bip39.validateMnemonic(_seedPhraseController.text);

    if (!isValid) {
      showArDriveDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.triangle(
              size: 88,
              color: ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
            ),
            title: appLocalizationsOf(context).error,
            // TODO: create/update localization key
            content:
                'The seed phrase you have provided is invalid. Please correct and retry.',
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

    context
        .read<LoginBloc>()
        .add(AddWalletFromMnemonic(_seedPhraseController.text));
  }
}
