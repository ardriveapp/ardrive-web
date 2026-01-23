import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboErrorView extends StatelessWidget {
  const TurboErrorView({
    super.key,
    required this.errorType,
    required this.onTryAgain,
    required this.onDismiss,
  });

  final TurboErrorType errorType;
  final Function onTryAgain;
  final Function onDismiss;

  String _getErrorMessageForErrorType(BuildContext context) {
    switch (errorType) {
      case TurboErrorType.sessionExpired:
        return appLocalizationsOf(context).turboErrorMessageSessionExpired;
      case TurboErrorType.unknown:
        return appLocalizationsOf(context).turboErrorMessageUnknown;
      case TurboErrorType.server:
        return appLocalizationsOf(context).turboErrorMessageServer;
      case TurboErrorType.fetchPaymentIntentFailed:
        return appLocalizationsOf(context)
            .turboErrorMessageEstimationInformationFailed;
      case TurboErrorType.fetchEstimationInformationFailed:
        return appLocalizationsOf(context)
            .turboErrorMessageEstimationInformationFailed;
      case TurboErrorType.network:
        return appLocalizationsOf(context).turboErrorMessageNetwork;
      default:
        return appLocalizationsOf(context).turboErrorMessageUnknown;
    }
  }

  String _getErrorTitleForErrorType(BuildContext context) {
    switch (errorType) {
      case TurboErrorType.sessionExpired:
        return appLocalizationsOf(context).turboSessionExpiredTitle;
      default:
        return appLocalizationsOf(context).theresBeenAProblem;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use different view for session expired (not an error, just a state)
    if (errorType == TurboErrorType.sessionExpired) {
      return SessionExpiredView(
        onRefresh: () => onTryAgain(),
        onDismiss: () => onDismiss(),
      );
    }

    return ErrorView(
      errorMessage: _getErrorMessageForErrorType(context),
      errorTitle: _getErrorTitleForErrorType(context),
      onDismiss: () => onDismiss(),
      onTryAgain: () => onTryAgain(),
    );
  }
}

/// A view specifically for session expiration - less alarming than error view.
class SessionExpiredView extends StatelessWidget {
  const SessionExpiredView({
    super.key,
    required this.onRefresh,
    required this.onDismiss,
  });

  final VoidCallback onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveCard(
      height: 400,
      contentPadding: EdgeInsets.zero,
      content: Column(
        children: [
          // Close button
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 26, right: 26),
              child: ArDriveClickArea(
                child: GestureDetector(
                  onTap: () {
                    onDismiss();
                    Navigator.pop(context);
                  },
                  child: ArDriveIcons.x(),
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Refresh icon instead of error triangle
                  ArDriveIcons.refresh(
                    size: 48,
                    color: colors.themeFgMuted,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appLocalizationsOf(context).turboSessionExpiredTitle,
                    style: typography.heading5(
                      fontWeight: ArFontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appLocalizationsOf(context).turboErrorMessageSessionExpired,
                    textAlign: TextAlign.center,
                    style: typography.paragraphNormal(
                      color: colors.themeFgMuted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ArDriveButton(
                    maxHeight: 44,
                    maxWidth: 160,
                    text: appLocalizationsOf(context).refresh,
                    fontStyle: typography.paragraphLarge(
                      fontWeight: ArFontWeight.bold,
                      color: Colors.white,
                    ),
                    onPressed: onRefresh,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.errorMessage,
    required this.errorTitle,
    this.onTryAgain,
    required this.onDismiss,
  });

  final String errorMessage;
  final String errorTitle;
  final VoidCallback? onTryAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      height: 513,
      contentPadding: EdgeInsets.zero,
      content: Column(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 26, right: 26),
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: () {
                      onDismiss();
                      Navigator.pop(context);
                    },
                    child: ArDriveIcons.x(),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ArDriveIcons.triangle(
                  size: 50,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeErrorDefault,
                ),
                Text(errorTitle, style: ArDriveTypographyNew.of(context).heading5(
                  fontWeight: ArFontWeight.bold,
                )),
                const SizedBox(height: 16),
                Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: ArDriveTypographyNew.of(context).paragraphNormal(
                    fontWeight: ArFontWeight.bold,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.center,
              child: ArDriveButton(
                maxHeight: 44,
                maxWidth: 143,
                text: appLocalizationsOf(context).tryAgain,
                fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: Colors.white,
                ),
                onPressed: onTryAgain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
