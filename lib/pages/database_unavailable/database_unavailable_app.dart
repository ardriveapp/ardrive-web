import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// What the app shows in place of itself when its database will not open.
///
/// Every screen after the splash reads the database, so a database that fails
/// to open or migrate would otherwise leave the splash up for good. This runs
/// on its own, with nothing from the app's providers, and offers Try again
/// and the ways to get help the Help menu offers. Nothing here deletes or
/// changes the data.
class DatabaseUnavailableApp extends StatelessWidget {
  const DatabaseUnavailableApp({
    super.key,
    required this.onTryAgain,
    required this.onHelpCenter,
    required this.onShareLogs,
    this.dark = false,
  });

  final VoidCallback onTryAgain;
  final VoidCallback onHelpCenter;
  final Future<void> Function(LogExportInfo info) onShareLogs;

  /// Whether to show it in the dark theme, as the app would have been.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ArDriveApp(
      // ArDriveApp is dark unless it is handed the light theme.
      themeData: dark ? null : lightTheme(),
      builder: (context) => MaterialApp(
        title: 'ArDrive',
        debugShowCheckedModeBanner: false,
        theme: ArDriveTheme.of(context).themeData.materialThemeData.copyWith(
              scaffoldBackgroundColor:
                  ArDriveTheme.of(context).themeData.backgroundColor,
            ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DatabaseUnavailablePage(
          onTryAgain: onTryAgain,
          onHelpCenter: onHelpCenter,
          onShareLogs: onShareLogs,
        ),
      ),
    );
  }
}

class DatabaseUnavailablePage extends StatelessWidget {
  const DatabaseUnavailablePage({
    super.key,
    required this.onTryAgain,
    required this.onHelpCenter,
    required this.onShareLogs,
  });

  final VoidCallback onTryAgain;
  final VoidCallback onHelpCenter;
  final Future<void> Function(LogExportInfo info) onShareLogs;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    Widget button(String text, ButtonVariant variant, VoidCallback onPressed) =>
        ArDriveButtonNew(
          variant: variant,
          size: ArDriveButtonSize.large,
          typography: typography,
          maxWidth: double.infinity,
          onPressed: onPressed,
          text: text,
        );

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.databaseUnavailableTitle,
                  textAlign: TextAlign.center,
                  style: typography.heading4(
                    color: colors.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.databaseUnavailableBody,
                  textAlign: TextAlign.center,
                  style: typography.paragraphLarge(color: colors.textMid),
                ),
                const SizedBox(height: 24),
                button(strings.tryAgain, ButtonVariant.primary, onTryAgain),
                const SizedBox(height: 12),
                button(strings.helpCenter, ButtonVariant.outline, onHelpCenter),
                const SizedBox(height: 12),
                button(
                  strings.shareLogsText,
                  ButtonVariant.outline,
                  () => onShareLogs(LogExportInfo(
                    emailSubject: strings.shareLogsEmailSubject,
                    emailBody: strings.shareLogsEmailBody,
                    shareText: strings.shareLogsNativeShareText,
                    shareSubject: strings.shareLogsNativeShareSubject,
                    emailSupport: Resources.emailSupport,
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
