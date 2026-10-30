import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/drive_fingerprint.dart';
import 'package:ardrive/components/password_autofill.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_cubit.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the unlock dialog for the locked drive [driveId].
///
/// Everything it needs is read here, from the caller's context, because the
/// dialog is built in the root navigator's overlay, above the page's
/// providers.
Future<void> showUnlockDriveDialog(
  BuildContext context, {
  required String driveId,
}) {
  final user = context.read<ArDriveAuth>().currentUser;
  final syncCubit = context.read<SyncCubit>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  return showArDriveDialog(
    context,
    content: BlocProvider(
      create: (_) => UnlockDriveCubit(
        driveId: driveId,
        unlocker: context.read<DriveUnlocker>(),
        wallet: user.wallet,
        profileKey: user.cipherKey,
        syncDrives: (driveIds) => syncUnlockedDrives(syncCubit, driveIds),
        signInPassword: user.password,
      ),
      child: UnlockDriveDialog(
        walletAddress: user.walletAddress,
        onUnlocked: (openedDriveIds) =>
            _sayHowManyOpened(messenger, openedDriveIds.length),
      ),
    ),
  );
}

/// Syncs drives that were just unlocked: they have a row and a key now, and
/// nothing else under them.
///
/// A sync is refused while another runs - one at a time, never queued - so
/// this waits for the running one once and asks again.
///
/// It never asks the wallet again for other drives whose prompt was
/// cancelled: unlocking one drive is not a request to be prompted for the
/// rest.
Future<void> syncUnlockedDrives(
  SyncCubit syncCubit,
  List<String> driveIds,
) async {
  if (await syncCubit.syncDrives(driveIds, askWalletAgain: false)) {
    return;
  }

  await syncCubit.waitCurrentSync();
  await syncCubit.syncDrives(driveIds, askWalletAgain: false);
}

void _sayHowManyOpened(ScaffoldMessengerState? messenger, int count) {
  // One drive opening is visible in the list itself. More than one opening
  // from one password is the surprise worth a line.
  if (count < 2 || messenger == null || !messenger.mounted) {
    return;
  }

  final context = messenger.context;

  showArDriveToast(
    messenger,
    text: appLocalizationsOf(context).unlockedDrives(count),
    type: ArDriveStatusType.success,
  );
}

/// Asks for a locked drive's password.
///
/// The drive is named by its emoji and its shortened ID, because its name is
/// inside the metadata the password decrypts. "Wrong password" is said only
/// when decryption proves it; anything else that stops the check says the
/// network couldn't be reached; a wallet prompt that is cancelled says
/// nothing at all.
class UnlockDriveDialog extends StatefulWidget {
  const UnlockDriveDialog({super.key, this.onUnlocked, this.walletAddress});

  /// The account the drive password belongs to, for the browser's password
  /// manager. See [PasswordAutofillGroup].
  final String? walletAddress;

  /// Called once the drive opens, with every drive that opened.
  final void Function(List<String> openedDriveIds)? onUnlocked;

  @override
  State<UnlockDriveDialog> createState() => _UnlockDriveDialogState();
}

class _UnlockDriveDialogState extends State<UnlockDriveDialog> {
  final _password = TextEditingController();
  final _focus = FocusNode(debugLabel: 'unlockDrivePassword');
  bool _tryOthers = true;

  /// "Remember on this device", on by default (3.0 password design, D4).
  bool _remember = true;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) {
      return;
    }

    context.read<UnlockDriveCubit>().submit(
          password: _password.text,
          tryOthers: _tryOthers,
          remember: _remember,
        );
  }

  /// Back to the field, its text selected, so the next attempt is typed
  /// straight over the last.
  void _refocus() {
    _focus.requestFocus();
    _password.selection =
        TextSelection(baseOffset: 0, extentOffset: _password.text.length);
  }

  Widget _withAutofill(Widget field) {
    final address = widget.walletAddress;
    if (address == null) return field;
    return PasswordAutofillGroup(username: address, child: field);
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<UnlockDriveCubit>();

    return BlocConsumer<UnlockDriveCubit, UnlockDriveState>(
      listener: (context, state) {
        switch (state.status) {
          case UnlockDriveStatus.unlocked:
            if (widget.walletAddress != null) PasswordAutofillGroup.save();
            widget.onUnlocked?.call(state.openedDriveIds);
            Navigator.of(context).pop();
          case UnlockDriveStatus.wrongPassword:
          case UnlockDriveStatus.networkError:
          case UnlockDriveStatus.walletFailed:
          case UnlockDriveStatus.idle:
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _refocus();
            });
          case UnlockDriveStatus.working:
            break;
        }
      },
      builder: (context, state) {
        final working = state.status == UnlockDriveStatus.working;

        return ArDriveStandardModalNew(
          key: const Key('unlockDriveDialog'),
          title: strings.unlockDriveTitle,
          // Leaves like Cancel, which works while an unlock runs too.
          hasCloseButton: true,
          closeLabel: strings.close,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DriveFingerprint(driveId: cubit.driveId, size: 40),
                const SizedBox(height: ArDriveSpacing.xs),
                Text.rich(
                  TextSpan(
                    style: typography.paragraphNormal(color: colors.textMid),
                    children: ArDriveIdText.spansIn(
                      '${strings.lockedDriveName} · ${shortenId(cubit.driveId)}',
                      shortenId(cubit.driveId),
                      idStyle: typography.code(color: colors.textMid),
                    ),
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.lg),
                _withAutofill(ArDriveTextFieldNew(
                  key: const Key('unlockDrivePassword'),
                  controller: _password,
                  focusNode: _focus,
                  label: strings.drivePasswordLabel,
                  obscureText: true,
                  showObfuscationToggle: true,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  isEnabled: !working,
                  errorMessage: state.status == UnlockDriveStatus.wrongPassword
                      ? strings.unlockWrongPassword
                      : null,
                  showErrorMessage:
                      state.status == UnlockDriveStatus.wrongPassword,
                  onChanged: (_) {
                    cubit.edited();
                    // The Unlock button follows whether there is anything
                    // to try.
                    setState(() {});
                  },
                  onFieldSubmitted: (_) => _submit(),
                )),
                if (state.status == UnlockDriveStatus.networkError ||
                    state.status == UnlockDriveStatus.walletFailed) ...[
                  const SizedBox(height: ArDriveSpacing.xs),
                  // Read out when it appears: a failed unlock was silent.
                  Semantics(
                    liveRegion: true,
                    child: ArDriveStatusText(
                      key: const Key('unlockDriveNetworkError'),
                      text: state.status == UnlockDriveStatus.walletFailed
                          ? strings.unlockWalletFailed
                          : strings.unlockNetworkError,
                      type: ArDriveStatusType.error,
                    ),
                  ),
                ],
                if (cubit.hasOtherLockedDrives) ...[
                  const SizedBox(height: ArDriveSpacing.md),
                  ArDriveCheckBox(
                    key: const Key('unlockDriveTryOthers'),
                    title: strings.tryOnOtherLockedDrives,
                    checked: _tryOthers,
                    isDisabled: working,
                    onChange: (value) => setState(() => _tryOthers = value),
                  ),
                ],
                SizedBox(
                  height: cubit.hasOtherLockedDrives
                      ? ArDriveSpacing.xs
                      : ArDriveSpacing.md,
                ),
                ArDriveCheckBox(
                  key: const Key('unlockDriveRemember'),
                  title: strings.rememberOnThisDevice,
                  checked: _remember,
                  isDisabled: working,
                  onChange: (value) => setState(() => _remember = value),
                ),
              ],
            ),
          ),
          actions: [
            ModalAction.dismiss(
              action: () => Navigator.of(context).pop(),
              title: strings.cancelEmphasized,
            ),
            ModalAction(
              action: _submit,
              title: strings.unlock,
              isEnable: _password.text.isNotEmpty,
              isLoading: working,
            ),
          ],
        );
      },
    );
  }
}
