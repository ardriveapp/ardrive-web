import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// What the app shows in place of itself when its database will not open.
///
/// Every screen after the splash reads the database, so a database that fails
/// to open or migrate would otherwise leave the splash up for good. This runs
/// on its own, with nothing from the app's providers, and gives the user two
/// ways on: try again, or reset the data this device keeps and start fresh.
class DatabaseUnavailableApp extends StatelessWidget {
  const DatabaseUnavailableApp({
    super.key,
    required this.onTryAgain,
    required this.onReset,
    this.dark = false,
  });

  final VoidCallback onTryAgain;

  /// Whether to show it in the dark theme, as the app would have been.
  final bool dark;

  /// Deletes the local data and starts again. Completes with false if some
  /// of it would not go.
  final Future<bool> Function() onReset;

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
        home: DatabaseUnavailablePage(onTryAgain: onTryAgain, onReset: onReset),
      ),
    );
  }
}

class DatabaseUnavailablePage extends StatefulWidget {
  const DatabaseUnavailablePage({
    super.key,
    required this.onTryAgain,
    required this.onReset,
  });

  final VoidCallback onTryAgain;
  final Future<bool> Function() onReset;

  @override
  State<DatabaseUnavailablePage> createState() =>
      _DatabaseUnavailablePageState();
}

class _DatabaseUnavailablePageState extends State<DatabaseUnavailablePage> {
  var _resetting = false;
  var _resetFailed = false;

  Future<void> _reset() async {
    setState(() {
      _resetting = true;
      _resetFailed = false;
    });
    var deleted = false;
    try {
      deleted = await widget.onReset();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _resetting = false;
      _resetFailed = !deleted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

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
                ArDriveButtonNew(
                  variant: ButtonVariant.primary,
                  size: ArDriveButtonSize.large,
                  typography: typography,
                  maxWidth: double.infinity,
                  isDisabled: _resetting,
                  onPressed: widget.onTryAgain,
                  text: strings.tryAgain,
                ),
                const SizedBox(height: 32),
                Text(
                  strings.databaseUnavailableResetWarning,
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(color: colors.textMid),
                ),
                const SizedBox(height: 12),
                ArDriveButtonNew(
                  variant: ButtonVariant.outline,
                  size: ArDriveButtonSize.large,
                  typography: typography,
                  maxWidth: double.infinity,
                  isDisabled: _resetting,
                  onPressed: _reset,
                  text: strings.databaseUnavailableReset,
                ),
                if (_resetFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.databaseUnavailableResetFailed,
                    textAlign: TextAlign.center,
                    style: typography.paragraphNormal(color: colors.textRed),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
