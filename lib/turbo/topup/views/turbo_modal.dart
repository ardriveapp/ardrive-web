import 'package:ardrive/turbo/topup/views/turbo_payment_form.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

void showTurboModal(BuildContext context) {
  showAnimatedDialog(
    context,
    content: const TurboModal(),
    barrierDismissible: false,
    barrierColor:
        ArDriveTheme.of(context).themeData.colors.shadow.withOpacity(0.9),
  );
}

class TurboModal extends StatefulWidget {
  const TurboModal({super.key});

  @override
  State<TurboModal> createState() => _TurboModalState();
}

class _TurboModalState extends State<TurboModal> {
  @override
  Widget build(BuildContext context) {
    return ArDriveModal(
      hasCloseButton: true,
      contentPadding: EdgeInsets.zero,
      content: const TurboPaymentFormView(),
      constraints: BoxConstraints(
        maxWidth: 575,
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
    );
  }
}
