import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

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
          title: 'Update private drives',
          hasCloseButton: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state is PrivateDriveMigrationComplete) ...[
                const Text(
                  'Drive updates complete!',
                ),
              ] else ...[
                RichText(
                  text: TextSpan(
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textMid,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'The following private drives need to be updated to continue using them in the future. Learn more ',
                      ),
                      TextSpan(
                        text: 'here',
                        style: typography
                            .paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                                color: colorTokens.textOnPrimary)
                            .copyWith(
                              decoration: TextDecoration.underline,
                            ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            launchUrl(
                                Uri.parse(
                                    'https://docs.ar.io/build/advanced/arfs/upgrading-drives'),
                                mode: LaunchMode.externalApplication);
                          },
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                )
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: ArDriveScrollBar(
                      controller: _scrollController,
                      alwaysVisible: true,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 0),
                        controller: _scrollController,
                        shrinkWrap: true,
                        itemCount: drivesToMigrate.length,
                        itemBuilder: (BuildContext context, int index) {
                          final drive = drivesToMigrate[index];
                          final indicator = (completed.contains(drive))
                              ? Icon(
                                  Icons.check,
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
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(width: 12),
                                indicator,
                                const SizedBox(width: 8),
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
                const SizedBox(height: 16),
                Text(
                  appLocalizationsOf(context)
                      .migrationDrivePasswordPrompt(state.drive.name),
                  style: typography.paragraphNormal(color: colorTokens.textMid),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 16),
                Text(
                  errorMessage,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textRed,
                  ),
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
                    title: 'Update',
                  ),
                ]
              : [
                  ModalAction(
                    action: () {
                      context
                          .read<PrivateDriveMigrationBloc>()
                          .add(const PrivateDriveMigrationCheck());
                      Navigator.of(context).pop();
                    },
                    title: 'Close',
                    isEnable: state is! PrivateDriveMigrationInProgress,
                  ),
                  if (state is! PrivateDriveMigrationComplete) ...[
                    ModalAction(
                      action: () {
                        // Navigator.of(context).pop();
                        migrateBloc
                            .add(const PrivateDriveMigrationStartEvent());
                      },
                      title: 'Update',
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
    content: const PrivateDriveMigrationDialog(),
  );
}
