import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/open_drive_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Opens the "Open a drive" dialog from the sign-in screen or anywhere a
/// visitor can reach.
void showOpenDriveDialog(BuildContext context) {
  showArDriveDialog(
    context,
    useRootNavigator: false,
    content: BlocProvider(
      create: (context) => OpenDriveCubit(
        arweave: context.read<ArweaveService>(),
        driveDao: context.read<DriveDao>(),
      ),
      child: OpenDriveModal(router: context.read<AppRouterDelegate>()),
    ),
  );
}

/// One field for a drive ID or any ArDrive link, a key field when the drive
/// turns out to be private, and one button. The states are in
/// `open_drive_state.dart`.
class OpenDriveModal extends StatefulWidget {
  const OpenDriveModal({super.key, required this.router});

  final AppRouterDelegate router;

  @override
  State<OpenDriveModal> createState() => _OpenDriveModalState();
}

class _OpenDriveModalState extends State<OpenDriveModal> {
  final _inputController = TextEditingController();
  final _keyController = TextEditingController();
  final _inputFocus = FocusNode();

  /// The link's own key has been copied into the field, once.
  bool _prefilledKey = false;

  @override
  void initState() {
    super.initState();
    PlausibleEventTracker.trackPageview(page: PlausiblePageView.openDrivePage);
    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus && mounted) {
        context.read<OpenDriveCubit>().inputBlurred(_inputController.text);
      }
    });
    _applyPrefilledKey(context.read<OpenDriveCubit>().state);
  }

  /// Copies the key a pasted link carried into the key field, once, so the
  /// reader sees why the drive opened.
  void _applyPrefilledKey(OpenDriveState state) {
    if (_prefilledKey || state is! OpenDrivePrivate) return;

    final key = state.prefilledKey;
    if (key == null) return;

    _prefilledKey = true;
    _keyController.text = key;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _keyController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final strings = appLocalizationsOf(context);

    return BlocConsumer<OpenDriveCubit, OpenDriveState>(
      listener: (context, state) {
        if (state is OpenDriveOpened) {
          Navigator.of(context).pop();
          widget.router.openDriveAsVisitor(
            driveId: state.driveId,
            folderId: state.folderId,
            driveKey: state.driveKey,
          );
        } else {
          _applyPrefilledKey(state);
        }
      },
      builder: (context, state) {
        final busy = state is OpenDriveOpening;

        return SingleChildScrollView(
          child: ArDriveLoginModal(
            width: 450,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ArDriveImage(
                    image: AssetImage(Resources.images.brand.logo1),
                    height: 36,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.openDriveTitle,
                  textAlign: TextAlign.center,
                  style: typography.heading2(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.openDriveDescription,
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: 32),
                ArDriveTextFieldNew(
                  key: const Key('openDriveInput'),
                  controller: _inputController,
                  focusNode: _inputFocus,
                  autofocus: true,
                  isEnabled: !busy,
                  label: strings.openDriveInputLabel,
                  hintText: strings.openDriveInputHint,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) =>
                      context.read<OpenDriveCubit>().inputChanged(value),
                  onFieldSubmitted: (_) => _submit(context, state),
                  showErrorMessage: false,
                ),
                const SizedBox(height: 8),
                _InputStatus(state: state),
                if (state is OpenDrivePrivate) ...[
                  const SizedBox(height: 16),
                  ArDriveTextFieldNew(
                    key: const Key('openDriveKeyInput'),
                    controller: _keyController,
                    autofocus: state.prefilledKey == null,
                    isEnabled: !busy,
                    obscureText: true,
                    showObfuscationToggle: true,
                    label: strings.openDriveKeyLabel,
                    onChanged: (value) =>
                        context.read<OpenDriveCubit>().keyChanged(value),
                    onFieldSubmitted: (_) => _submit(context, state),
                    showErrorMessage: false,
                  ),
                  const SizedBox(height: 8),
                  _KeyStatus(state: state),
                ],
                const SizedBox(height: 32),
                ArDriveButtonNew(
                  size: ArDriveButtonSize.large,
                  key: const Key('openDriveButton'),
                  text: _buttonText(strings, state),
                  typography: typography,
                  variant: ButtonVariant.primary,
                  maxWidth: double.maxFinite,
                  isDisabled: busy || !state.canOpen,
                  onPressed: () => _submit(context, state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buttonText(AppLocalizations strings, OpenDriveState state) {
    return switch (state) {
      OpenDriveOpening() => strings.openDriveOpening,
      OpenDriveOtherLink(isFile: true) => strings.openDriveOpenFileButton,
      OpenDriveOtherLink() => strings.openDriveOpenTransactionButton,
      _ => strings.openDriveButton,
    };
  }

  void _submit(BuildContext context, OpenDriveState state) {
    if (!state.canOpen) return;

    if (state is OpenDriveOtherLink) {
      Navigator.of(context).pop();
      widget.router.openRouteAsVisitor(state.route);
      return;
    }

    context.read<OpenDriveCubit>().open();
  }
}

/// What the dialog says under the first field.
class _InputStatus extends StatelessWidget {
  const _InputStatus({required this.state});

  final OpenDriveState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final errorColor = colorTokens.statusErrorFg;
    final typography = ArDriveTypographyNew.of(context);

    Widget line(String text, Color color, {Key? key}) => Text(
          text,
          key: key,
          style: typography.paragraphSmall(color: color),
        );

    return switch (state) {
      OpenDriveLookingUp() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ArDriveLinearProgress(),
            const SizedBox(height: 6),
            line(strings.attachDriveLookingUp, colorTokens.textLow),
          ],
        ),
      OpenDrivePublic(name: final name) => line(
          strings.openDriveFoundPublic(name),
          colorTokens.textHigh,
          key: const Key('openDriveFound'),
        ),
      OpenDrivePrivate() => line(
          strings.openDrivePrivateNeedsKey,
          colorTokens.textLow,
        ),
      OpenDriveOtherLink(:final isFile) => line(
          isFile
              ? strings.openDriveFileLinkDetected
              : strings.openDriveTransactionLinkDetected,
          colorTokens.textHigh,
        ),
      OpenDriveNotFound() => line(
          strings.openDriveNotFound,
          errorColor,
          key: const Key('openDriveError'),
        ),
      OpenDriveNetworkError() => line(
          strings.openDriveNetworkError,
          errorColor,
          key: const Key('openDriveError'),
        ),
      OpenDriveUnrecognisedInput() => line(
          strings.openDriveUnrecognisedInput,
          errorColor,
          key: const Key('openDriveError'),
        ),
      OpenDriveFailure() => line(
          strings.openDriveFailed,
          errorColor,
          key: const Key('openDriveError'),
        ),
      OpenDriveInitial() ||
      OpenDriveOpening() ||
      OpenDriveOpened() =>
        const SizedBox(height: 16),
    };
  }
}

/// What the dialog says under the key field.
class _KeyStatus extends StatelessWidget {
  const _KeyStatus({required this.state});

  final OpenDrivePrivate state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final errorColor = colorTokens.statusErrorFg;
    final typography = ArDriveTypographyNew.of(context);

    if (state.validating) {
      return const ArDriveLinearProgress();
    }

    if (state.keyRejected) {
      return Text(
        strings.openDriveKeyRejected,
        key: const Key('openDriveKeyError'),
        style: typography.paragraphSmall(color: errorColor),
      );
    }

    if (state.name != null) {
      return Text(
        strings.openDriveFoundPrivate(state.name!),
        key: const Key('openDriveFound'),
        style: typography.paragraphSmall(color: colorTokens.textHigh),
      );
    }

    return const SizedBox(height: 16);
  }
}
