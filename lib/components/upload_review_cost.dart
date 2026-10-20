import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The cost from the step before, kept on the last step so the price is on
/// screen when the person presses Upload.
class UploadReviewCost extends StatelessWidget {
  const UploadReviewCost({super.key, required this.paymentInfo});

  final UploadPaymentMethodInfo paymentInfo;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.only(bottom: 16);

    if (paymentInfo.isFreeThanksToTurbo) {
      return TurboFreeStatusMessage(
        status: paymentInfo.freeStatus,
        padding: padding,
      );
    }

    final l10n = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final turboCost = paymentInfo.costEstimateTurbo;

    return Padding(
      padding: padding,
      child: Text(
        paymentInfo.uploadMethod == UploadMethod.turbo && turboCost != null
            ? l10n.costCredits(convertWinstonToCostString(turboCost.totalCost))
            : l10n.cost(convertWinstonToCostString(
                paymentInfo.costEstimateAr.totalCost)),
        style: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.bold,
        ),
      ),
    );
  }
}
