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
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveCard(
      contentPadding: EdgeInsets.zero,
      content: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Red top line (ArDrive modal pattern)
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: colorTokens.containerRed,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title - left aligned
                    Text(
                      appLocalizationsOf(context).turboSessionExpiredTitle,
                      style: typography.heading5(
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Icon and message
                    Row(
                      children: [
                        ArDriveIcons.refresh(
                          size: 32,
                          color: colors.themeFgMuted,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            appLocalizationsOf(context)
                                .turboErrorMessageSessionExpired,
                            style: typography.paragraphNormal(
                              color: colors.themeFgMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Action button
                    Align(
                      alignment: Alignment.centerRight,
                      child: ArDriveButton(
                        maxHeight: 44,
                        maxWidth: 160,
                        text: appLocalizationsOf(context).refresh,
                        fontStyle: typography.paragraphLarge(
                          fontWeight: ArFontWeight.bold,
                          color: Colors.white,
                        ),
                        onPressed: onRefresh,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Close button in top right
          Positioned(
            right: 20,
            top: 20,
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
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveCard(
      contentPadding: EdgeInsets.zero,
      content: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Red top line (ArDrive modal pattern)
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: colorTokens.containerRed,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title - left aligned
                    Text(
                      errorTitle,
                      style: typography.heading5(
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Icon and message
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ArDriveIcons.triangle(
                          size: 32,
                          color: colors.themeErrorDefault,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            errorMessage,
                            style: typography.paragraphNormal(
                              color: colors.themeFgMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Action button
                    Align(
                      alignment: Alignment.centerRight,
                      child: ArDriveButton(
                        maxHeight: 44,
                        maxWidth: 143,
                        text: appLocalizationsOf(context).tryAgain,
                        fontStyle: typography.paragraphLarge(
                          fontWeight: ArFontWeight.bold,
                          color: Colors.white,
                        ),
                        onPressed: onTryAgain,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Close button in top right
          Positioned(
            right: 20,
            top: 20,
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
        ],
      ),
    );
  }
}
