import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TopUpDialog extends StatefulWidget {
  const TopUpDialog({super.key});

  @override
  State<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<TopUpDialog> {
  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      title: 'turbo',
      content: Container(),
    );
  }
}
