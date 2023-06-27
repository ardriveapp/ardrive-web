import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
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

  String _getErrorMessageForErrorType() {
    switch (errorType) {
      case TurboErrorType.sessionExpired:
        return 'Your session has expired. Please try again.';
      case TurboErrorType.unknown:
        return 'The payment was not successful. Please check your card information and try again.';
      case TurboErrorType.server:
        return 'The payment was not successful. Please check your card information and try again.';
      case TurboErrorType.fetchPaymentIntentFailed:
        return 'Payment processor is currently unavailable, please try again later';
      case TurboErrorType.fetchEstimationInformationFailed:
        return 'Error loading information. Please try again.';
      default:
        return 'The payment was not successful. Please check your card information and try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      height: 513,
      contentPadding: EdgeInsets.zero,
      content: Column(
        children: [
          Flexible(
            flex: 1,
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
                      child: ArDriveIcons.x()),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 1,
            child: Column(
              children: [
                ArDriveIcons.triangle(
                  size: 50,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeErrorDefault,
                ),
                Text('There\'s been a problem.',
                    style: ArDriveTypography.body.leadBold()),
                const SizedBox(height: 16),
                Text(
                  _getErrorMessageForErrorType(),
                  style: ArDriveTypography.body.buttonNormalRegular(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
              child: ArDriveButton(
                maxHeight: 44,
                maxWidth: 143,
                // TODO: localize
                text: 'Try Again',
                fontStyle: ArDriveTypography.body.buttonLargeBold(
                  color: Colors.white,
                ),
                onPressed: () {
                  onTryAgain();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
