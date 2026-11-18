import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../utils/show_general_dialog.dart';

Future<void> attachDrive({
  required BuildContext context,
  DriveID? driveId,
  String? driveName,
  DriveKey? driveKey,
}) {
  final profileState = context.read<ProfileCubit>().state;
  final profileKey =
      profileState is ProfileLoggedIn ? profileState.user.cipherKey : null;
  return showModalDialog(
    context,
    () => showArDriveDialog(
      context,
      barrierDismissible: false,
      content: BlocProvider<DriveAttachCubit>(
        create: (context) => DriveAttachCubit(
          initialDriveId: driveId,
          initialDriveName: driveName,
          initialDriveKey: driveKey,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          syncBloc: context.read<SyncCubit>(),
          activityCubit: context.read<ActivityCubit>(),
          drivesBloc: context.read<DrivesCubit>(),
          profileKey: profileKey,
        ),
        child: BlocListener<DriveAttachCubit, DriveAttachState>(
          listener: (context, state) {
            // A failure is said in the dialog, which stays open to try again.
            if (state is DriveAttachSuccess) {
              Navigator.pop(context);
            }
          },
          child: const DriveAttachForm(),
        ),
      ),
    ),
  );
}

/// Depends on a provided [DriveAttachCubit] for business logic.
class DriveAttachForm extends StatefulWidget {
  const DriveAttachForm({super.key});

  @override
  State<DriveAttachForm> createState() => _DriveAttachFormState();
}

/// What the last attempt or lookup found, said in the dialog.
enum _AttachProblem { none, notFound, invalidKey, failed }

class _DriveAttachFormState extends State<DriveAttachForm> {
  bool _isFormValid = false;
  _AttachProblem _problem = _AttachProblem.none;

  // The drive is private: its key field stays while the attach runs, though
  // the state is then in progress.
  bool _isPrivate = false;

  late final DriveAttachCubit _cubit = context.read<DriveAttachCubit>();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cubit.driveNameController.addListener(_onDriveNameChange);
      _cubit.driveIdController.addListener(_onDriveIdOrKeyChange);
      _cubit.driveKeyController.addListener(_onDriveIdOrKeyChange);
    });
  }

  @override
  void dispose() {
    _cubit.driveNameController.removeListener(_onDriveNameChange);
    _cubit.driveIdController.removeListener(_onDriveIdOrKeyChange);
    _cubit.driveKeyController.removeListener(_onDriveIdOrKeyChange);
    super.dispose();
  }

  void _onDriveNameChange() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isFormValid = _cubit.driveNameController.text.isNotEmpty;
    });
  }

  // Typing a different ID or key clears what was said about the last one.
  void _onDriveIdOrKeyChange() {
    if (!mounted || _problem == _AttachProblem.none) return;
    if (_problem == _AttachProblem.failed) return;
    setState(() => _problem = _AttachProblem.none);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);

    return BlocConsumer<DriveAttachCubit, DriveAttachState>(
      listener: (context, state) {
        if (state is DriveAttachPrivate) {
          _isPrivate = true;
        } else if (state is DriveAttachInvalidDriveKey) {
          setState(() => _problem = _AttachProblem.invalidKey);
        } else if (state is DriveAttachDriveNotFound) {
          setState(() => _problem = _AttachProblem.notFound);
        } else if (state is DriveAttachFailure) {
          setState(() => _problem = _AttachProblem.failed);
        } else if (state is DriveAttachInProgress) {
          setState(() => _problem = _AttachProblem.none);
        }
      },
      builder: (context, state) {
        final busy = state is DriveAttachInProgress;
        final showKey = state is DriveAttachPrivate || (busy && _isPrivate);
        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
        final typography = ArDriveTypographyNew.of(context);

        return ArDriveStandardModalNew(
          title: l10n.attachDriveEmphasized,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArDriveTextFieldNew(
                controller: _cubit.driveIdController,
                autofocus: true,
                label: l10n.driveID,
                isEnabled: !busy,
                // An ID, so monospace, at a size where all 36 characters
                // of a drive ID fit the field: a step smaller, it scrolled
                // its start out of sight.
                textStyle: typography.code(fontSize: 12),
                onChanged: (s) async {
                  // Only look up when drive ID looks complete (UUID = 36 chars)
                  if (s.length >= 36) {
                    debounce(() {
                      if (!mounted) return;
                      _cubit.drivePrivacyLoader();
                    });
                  }
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _cubit.lookupNotifier,
                builder: (context, isLoading, _) {
                  if (!isLoading) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: ArDriveSpacing.xs),
                    child: Column(
                      children: [
                        const ArDriveLinearProgress(),
                        const SizedBox(height: ArDriveSpacing.xxs),
                        Text(
                          l10n.attachDriveLookingUp,
                          style: typography.paragraphSmall(
                            color: colorTokens.textLow,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (showKey) ...[
                const SizedBox(height: ArDriveSpacing.xs),
                Text(
                  l10n.attachDrivePrivateFound,
                  style: typography.paragraphSmall(
                    color: colorTokens.textLow,
                  ),
                ),
              ],
              const SizedBox(height: ArDriveSpacing.md),
              if (showKey) ...[
                ArDriveTextFieldNew(
                  controller: _cubit.driveKeyController,
                  autofocus: true,
                  label: l10n.driveKey,
                  isEnabled: !busy,
                  obscureText: true,
                  // A key, so monospace.
                  textStyle: typography.code(),
                  onChanged: (s) async {},
                  asyncValidator: (s) async {
                    final validation = await _cubit.driveKeyValidator();

                    if (!mounted) {
                      logger.i(
                          'Drive attach form closed. Not validating drive key.');
                      return null;
                    }

                    return validation;
                  },
                ),
                const SizedBox(height: ArDriveSpacing.md),
              ],
              ArDriveTextFieldNew(
                controller: _cubit.driveNameController,
                label: l10n.driveName,
                isEnabled: !busy,
                onChanged: (s) async {},
                asyncValidator: (s) async {
                  final nameValidation = validateEntityName(s, context);

                  setState(() {
                    _isFormValid = nameValidation == null;
                  });

                  return nameValidation;
                },
              ),
              if (_cubit.cachedDriveEntity != null) ...[
                const SizedBox(height: ArDriveSpacing.sm),
                _DriveInfoRow(entity: _cubit.cachedDriveEntity!),
              ],
              if (_problem != _AttachProblem.none && !busy) ...[
                const SizedBox(height: ArDriveSpacing.md),
                ArDriveNotice(
                  type: ArDriveNoticeType.error,
                  message: switch (_problem) {
                    _AttachProblem.notFound =>
                      l10n.validationAttachDriveCouldNotBeFound,
                    _AttachProblem.invalidKey => l10n.attachDriveInvalidKey,
                    _ => l10n.actionFailedTryAgain,
                  },
                  actionLabel:
                      _problem == _AttachProblem.failed ? l10n.tryAgain : null,
                  onAction: _problem == _AttachProblem.failed
                      ? () {
                          setState(() => _problem = _AttachProblem.none);
                          _cubit.submit();
                        }
                      : null,
                  onDismiss: () =>
                      setState(() => _problem = _AttachProblem.none),
                  dismissLabel: l10n.close,
                ),
              ],
            ],
          ),
          actions: [
            ModalAction.close(
              action: () => Navigator.of(context).pop(null),
              title: l10n.cancelEmphasized,
              isEnable: !busy,
            ),
            ModalAction(
              isEnable: _isFormValid,
              isLoading: busy,
              action: () => _cubit.submit(),
              title: l10n.attachEmphasized,
            ),
          ],
        );
      },
    );
  }
}

class _DriveInfoRow extends StatelessWidget {
  final DriveEntity entity;

  const _DriveInfoRow({required this.entity});

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final owner = entity.ownerAddress;
    final truncatedOwner = shortenId(owner);
    final dateStr = formatDate(entity.createdAt);
    final l10n = appLocalizationsOf(context);

    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
        color: colorTokens.containerL1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.searchDriveResult(entity.privacy ?? 'public'),
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textMid,
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.xxs),
                // The address in monospace, the label around it in the body
                // face. The whole address is in the tooltip, which a screen
                // reader announces too: at a large text size on a phone the
                // shortened one can be cut short.
                ArDriveTooltip(
                  message: owner,
                  child: Text.rich(
                    TextSpan(
                      style: typography.paragraphSmall(
                        color: colorTokens.textLow,
                      ),
                      children: ArDriveIdText.spansIn(
                        l10n.attachDriveOwner(truncatedOwner),
                        truncatedOwner,
                        idStyle: typography.code(
                          color: colorTokens.textLow,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            dateStr,
            style: typography.paragraphSmall(
              color: colorTokens.textLow,
            ),
          ),
        ],
      ),
    );
  }
}
