import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ardrive/utils/open_url.dart';

class PrivateDriveMigrationDialog extends StatefulWidget {
  const PrivateDriveMigrationDialog({super.key});

  @override
  State<PrivateDriveMigrationDialog> createState() =>
      _PrivateDriveMigrationDialogState();
}

class _PrivateDriveMigrationDialogState
    extends State<PrivateDriveMigrationDialog> {
  final _scrollController = ScrollController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _answer(String? password) {
    context
        .read<PrivateDriveMigrationBloc>()
        .add(PrivateDriveMigrationPasswordEntered(password));
    _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PrivateDriveMigrationBloc, PrivateDriveMigrationState>(
      builder: (context, state) {
        if (state is PrivateDriveMigrationHidden) {
          return const SizedBox.shrink();
        }

        final typography = ArDriveTypographyNew.of(context);
        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

        final migrateBloc = context.read<PrivateDriveMigrationBloc>();
        final drivesToMigrate = migrateBloc.drivesRequiringMigration;

        final Set<Drive> completed = migrateBloc.completedMigration;

        final driveInProgress = state is PrivateDriveMigrationInProgress
            ? state.inProgressDrive
            : null;

        final errorMessage =
            state is PrivateDriveMigrationFailed ? state.error : null;

        return ArDriveStandardModalNew(
          title: appLocalizationsOf(context).updatePrivateDrives,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state is PrivateDriveMigrationComplete)
                Text(
                  appLocalizationsOf(context).privateDrivesUpdated,
                  style: typography.paragraphNormal(color: colorTokens.textMid),
                )
              else
                Text.rich(
                  TextSpan(
                    style:
                        typography.paragraphNormal(color: colorTokens.textMid),
                    children: [
                      TextSpan(
                        text:
                            appLocalizationsOf(context).privateDrivesNeedUpdate,
                      ),
                      const TextSpan(text: ' '),
                      ArDriveLink.span(
                        text: appLocalizationsOf(context).learnMore,
                        external: true,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                        onTap: () => openUrl(
                          url:
                              'https://docs.ar.io/build/advanced/arfs/upgrading-drives',
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: ArDriveSpacing.md),
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: ArDriveScrollBar(
                      controller: _scrollController,
                      alwaysVisible: true,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        controller: _scrollController,
                        shrinkWrap: true,
                        itemCount: drivesToMigrate.length,
                        itemBuilder: (BuildContext context, int index) {
                          final drive = drivesToMigrate[index];
                          final indicator = (completed.contains(drive))
                              ? ArDriveIcons.checkmark(
                                  size: 16.0,
                                  color: colorTokens.statusSuccessFg,
                                )
                              : (drive == driveInProgress)
                                  ? const ArDriveSpinner()
                                  : ArDriveIcons.privateDrive(
                                      size: 16.0,
                                      color: colorTokens.textMid,
                                    );
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: ArDriveSpacing.xxs),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(width: ArDriveSpacing.sm),
                                indicator,
                                const SizedBox(width: ArDriveSpacing.xs),
                                Flexible(
                                  child: Text(
                                    drive.name,
                                    style: typography.paragraphNormal(
                                        color: colorTokens.textMid),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )),
                ),
              ),
              // A drive whose key the sign-in password doesn't make: its
              // own password, or skip it.
              if (state is PrivateDriveMigrationNeedsPassword) ...[
                const SizedBox(height: ArDriveSpacing.md),
                Text(
                  appLocalizationsOf(context)
                      .migrationDrivePasswordPrompt(state.drive.name),
                  style: typography.paragraphNormal(color: colorTokens.textMid),
                ),
                const SizedBox(height: ArDriveSpacing.xs),
                ArDriveTextFieldNew(
                  key: const Key('migrationDrivePassword'),
                  controller: _password,
                  label: appLocalizationsOf(context).drivePasswordLabel,
                  obscureText: true,
                  showObfuscationToggle: true,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  errorMessage: state.wrongPassword
                      ? appLocalizationsOf(context).unlockWrongPassword
                      : null,
                  showErrorMessage: state.wrongPassword,
                  onFieldSubmitted: (value) => _answer(value),
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: ArDriveSpacing.md),
                ArDriveNotice(
                  type: ArDriveNoticeType.error,
                  // The bloc's own text is English and for the log.
                  message:
                      appLocalizationsOf(context).privateDrivesUpdateFailed,
                ),
              ]
            ],
          ),
          actions: state is PrivateDriveMigrationNeedsPassword
              ? [
                  ModalAction.dismiss(
                    action: () => _answer(null),
                    title: appLocalizationsOf(context).skip,
                  ),
                  ModalAction(
                    action: () => _answer(_password.text),
                    title: appLocalizationsOf(context).updateAction,
                  ),
                ]
              : [
                  ModalAction.close(
                    action: () {
                      context
                          .read<PrivateDriveMigrationBloc>()
                          .add(const PrivateDriveMigrationCheck());
                      Navigator.of(context).pop();
                    },
                    title: appLocalizationsOf(context).close,
                    isEnable: state is! PrivateDriveMigrationInProgress,
                  ),
                  if (state is! PrivateDriveMigrationComplete) ...[
                    ModalAction(
                      action: () {
                        // Navigator.of(context).pop();
                        migrateBloc
                            .add(const PrivateDriveMigrationStartEvent());
                      },
                      title: appLocalizationsOf(context).updateAction,
                      isEnable: state is! PrivateDriveMigrationInProgress,
                    ),
                  ],
                ],
        );
      },
    );
  }
}

void showMigratePrivateDrivesModal(BuildContext context) {
  showArDriveDialog(
    context,
    barrierDismissible: false,
    content: const PrivateDriveMigrationDialog(),
  );
}
