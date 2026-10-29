import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:flutter/material.dart';

/// The cost from the step before, kept on the last step so the price is on
/// screen when the person presses Upload. The same cost block as the review.
class UploadReviewCost extends StatelessWidget {
  const UploadReviewCost({super.key, required this.paymentInfo});

  final UploadPaymentMethodInfo paymentInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: UploadCostBlock(
        summary: UploadReviewSummary.fromPaymentInfo(paymentInfo),
      ),
    );
  }
}
