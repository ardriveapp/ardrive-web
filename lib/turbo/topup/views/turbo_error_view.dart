import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
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

  String _getErrorMessageForErrorType(BuildContext context) =>
      turboErrorMessage(context, errorType);

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
    // Not an error, just a state: an info notice, and Refresh.
    return TurboTopupScaffold(
      title: appLocalizationsOf(context).turboSessionExpiredTitle,
      onClose: () {
        onDismiss();
        Navigator.pop(context);
      },
      actions: [
        ModalAction(
          title: appLocalizationsOf(context).refresh,
          action: onRefresh,
        ),
      ],
      child: ArDriveNotice(
        type: ArDriveNoticeType.info,
        message: appLocalizationsOf(context).turboErrorMessageSessionExpired,
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
    final onTryAgain = this.onTryAgain;

    return TurboTopupScaffold(
      title: errorTitle,
      onClose: () {
        onDismiss();
        Navigator.pop(context);
      },
      actions: [
        if (onTryAgain != null)
          ModalAction(
            title: appLocalizationsOf(context).tryAgain,
            action: onTryAgain,
          ),
      ],
      child: ArDriveNotice(
        type: ArDriveNoticeType.error,
        message: errorMessage,
      ),
    );
  }
}

/// What to tell someone about a top-up error of [errorType].
String turboErrorMessage(BuildContext context, TurboErrorType errorType) {
  switch (errorType) {
    case TurboErrorType.sessionExpired:
      return appLocalizationsOf(context).turboErrorMessageSessionExpired;
    case TurboErrorType.unknown:
      return appLocalizationsOf(context).turboErrorMessageUnknown;
    case TurboErrorType.paymentFailed:
      return appLocalizationsOf(context).turboErrorMessagePaymentFailed;
    case TurboErrorType.paymentCanceled:
      return appLocalizationsOf(context).turboErrorMessagePaymentCanceled;
    case TurboErrorType.server:
      return appLocalizationsOf(context).turboErrorMessageServer;
    case TurboErrorType.fetchPaymentIntentFailed:
      return appLocalizationsOf(context)
          .turboErrorMessageFetchPaymentIntentFailed;
    case TurboErrorType.fetchEstimationInformationFailed:
      return appLocalizationsOf(context)
          .turboErrorMessageEstimationInformationFailed;
    case TurboErrorType.network:
      return appLocalizationsOf(context).turboErrorMessageNetwork;
    default:
      return appLocalizationsOf(context).turboErrorMessageUnknown;
  }
}
