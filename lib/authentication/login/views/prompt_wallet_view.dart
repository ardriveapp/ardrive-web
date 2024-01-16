import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../misc/resources.dart';
import '../../../pages/drive_detail/components/hover_widget.dart';
import '../../../services/config/config_service.dart';
import '../../../utils/app_localizations_wrapper.dart';
import '../../../utils/open_url.dart';
import 'login_card.dart';
import 'max_device_sizes_constrained_box.dart';

class PromptWalletView extends StatefulWidget {
  final bool isArConnectAvailable;

  const PromptWalletView({
    super.key,
    required this.isArConnectAvailable,
  });

  @override
  State<PromptWalletView> createState() => _PromptWalletViewState();
}

class _PromptWalletViewState extends State<PromptWalletView> {
  late ArDriveDropAreaSingleInputController _dropAreaController;

  @override
  void initState() {
    _dropAreaController = ArDriveDropAreaSingleInputController(
      onFileAdded: (file) {
        context.read<LoginBloc>().add(AddWalletFile(file));
      },
      validateFile: (file) async {
        final wallet =
            await context.read<LoginBloc>().validateAndReturnWalletFile(file);

        return wallet != null;
      },
      onDragEntered: () {},
      onDragExited: () {},
      onError: (Object e) {},
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return MaxDeviceSizesConstrainedBox(
      defaultMaxWidth: 512,
      defaultMaxHeight: 798,
      maxHeightPercent: 0.9,
      child: SingleChildScrollView(
        child: LoginCard(
          content: Column(
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
              heightSpacing(),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  appLocalizationsOf(context).login,
                  style: ArDriveTypography.headline.headline4Regular(),
                ),
              ),
              heightSpacing(),
              Column(
                children: [
                  if (context
                      .read<ConfigService>()
                      .config
                      .enableSeedPhraseLogin) ...[
                    ArDriveButton(
                      icon: ArDriveIcons.keypad(
                          size: 24, color: colors.themeFgDefault),
                      key: const Key('loginWithSeedPhraseButton'),
                      // TODO: create/update localization key
                      text: 'Enter Seed Phrase',
                      onPressed: () {
                        context.read<LoginBloc>().add(const EnterSeedPhrase());
                      },
                      style: ArDriveButtonStyle.secondary,
                      fontStyle: ArDriveTypography.body.smallBold700(
                        color: colors.themeFgDefault,
                      ),
                      maxWidth: double.maxFinite,
                    ),
                    const SizedBox(height: 16),
                  ],
                  ArDriveDropAreaSingleInput(
                    controller: _dropAreaController,
                    keepButtonVisible: true,
                    width: double.maxFinite,
                    // TODO: create/update localization key
                    dragAndDropDescription: 'Select a KeyFile',
                    dragAndDropButtonTitle: 'Select a KeyFile',
                    errorDescription:
                        appLocalizationsOf(context).invalidKeyFile,
                    validateFile: (file) async {
                      final wallet = await context
                          .read<LoginBloc>()
                          .validateAndReturnWalletFile(file);

                      return wallet != null;
                    },
                    platformSupportsDragAndDrop: !AppPlatform.isMobile,
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      openUrl(
                        url: Resources.howDoesKeyFileLoginWork,
                      );
                    },
                    child: HoverWidget(
                      hoverScale: 1,
                      child: Text(
                          appLocalizationsOf(context).howDoesKeyfileLoginWork,
                          style: ArDriveTypography.body.smallBold().copyWith(
                                decoration: TextDecoration.underline,
                                fontSize: 14,
                                height: 1.5,
                              )),
                    ),
                  ),
                  if (widget.isArConnectAvailable) ...[
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        Expanded(
                            child: Container(
                          decoration: const ShapeDecoration(
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                width: 0.50,
                                strokeAlign: BorderSide.strokeAlignCenter,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        )),
                        Padding(
                            padding: const EdgeInsets.only(left: 25, right: 25),
                            child: Text(
                              'OR',
                              textAlign: TextAlign.center,
                              style: ArDriveTypography.body
                                  .smallBold(color: const Color(0xFF9E9E9E)),
                            )),
                        Expanded(
                            child: Container(
                          decoration: const ShapeDecoration(
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                width: 0.50,
                                strokeAlign: BorderSide.strokeAlignCenter,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        )),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: ArDriveButton(
                              icon: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: ArDriveIcons.arconnectIcon1(
                                    color: colors.themeFgDefault,
                                  )),
                              style: ArDriveButtonStyle.secondary,
                              fontStyle: ArDriveTypography.body
                                  .smallBold700(color: colors.themeFgDefault),
                              onPressed: () {
                                context
                                    .read<LoginBloc>()
                                    .add(const AddWalletFromArConnect());
                              },
                              // TODO: create/update localization key
                              text: 'Login with ArConnect',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(
                    height: 72,
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      // TODO: create/update localization key
                      text: 'New user? Get started here!',
                      style: ArDriveTypography.body
                          .smallBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgMuted)
                          .copyWith(decoration: TextDecoration.underline),

                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          context
                              .read<LoginBloc>()
                              .add(const CreateNewWallet());
                        },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SizedBox heightSpacing() {
    return SizedBox(
        height: MediaQuery.of(context).size.height < 700 ? 8.0 : 24.0);
  }
}
