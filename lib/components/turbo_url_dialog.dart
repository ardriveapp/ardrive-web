import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboUrlDialog extends StatefulWidget {
  final String initialUploadUrl;
  final String initialPaymentUrl;
  final void Function(String uploadUrl, String paymentUrl) onSave;

  const TurboUrlDialog({
    super.key,
    required this.initialUploadUrl,
    required this.initialPaymentUrl,
    required this.onSave,
  });

  @override
  State<TurboUrlDialog> createState() => _TurboUrlDialogState();
}

class _TurboUrlDialogState extends State<TurboUrlDialog> {
  late final TextEditingController _uploadController;
  late final TextEditingController _paymentController;
  bool _isValid = true;

  @override
  void initState() {
    super.initState();
    _uploadController = TextEditingController(text: widget.initialUploadUrl);
    _paymentController = TextEditingController(text: widget.initialPaymentUrl);
    _uploadController.addListener(_onChanged);
    _paymentController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _uploadController.removeListener(_onChanged);
    _paymentController.removeListener(_onChanged);
    _uploadController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      _isValid = _isValidUrl(_uploadController.text.trim()) &&
          _isValidUrl(_paymentController.text.trim());
    });
  }

  static bool _isValidUrl(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  static String? _validateUrl(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a URL';
    }
    if (!_isValidUrl(value)) {
      return 'Please enter a valid URL (e.g. https://upload.ardrive.io)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      width: 500,
      title: 'Turbo Service URLs',
      content: SizedBox(
        width: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configure the upload and payment service URLs.',
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: 16),
            ArDriveTextFieldNew(
              controller: _uploadController,
              hintText: 'https://upload.ardrive.io',
              label: 'Upload Service URL',
              validator: _validateUrl,
            ),
            const SizedBox(height: 16),
            ArDriveTextFieldNew(
              controller: _paymentController,
              hintText: 'https://payment.ardrive.io',
              label: 'Payment Service URL',
              validator: _validateUrl,
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          title: 'Cancel',
          action: () => Navigator.of(context).pop(),
        ),
        ModalAction(
          title: 'Save',
          isEnable: _isValid,
          action: () {
            widget.onSave(
              _uploadController.text.trim(),
              _paymentController.text.trim(),
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
