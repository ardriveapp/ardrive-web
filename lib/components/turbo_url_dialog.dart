import 'dart:async';

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboUrlDialog extends StatefulWidget {
  final String initialUploadUrl;
  final String initialPaymentUrl;
  final FutureOr<void> Function(String uploadUrl, String paymentUrl) onSave;

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

  /// True from the press until the save has finished: a second press must not
  /// save twice, and nothing here changes while it runs.
  bool _saving = false;
  bool _saveFailed = false;

  Future<void> _save(FutureOr<void> Function() save) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await save();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      logger.e('Failed to save the setting', e);
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

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

  String? _validateUrl(String? value) {
    final strings = appLocalizationsOf(context);
    if (value == null || value.isEmpty) {
      return strings.urlRequired;
    }
    if (!_isValidUrl(value)) {
      return strings.urlInvalid;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return PopScope(
        canPop: !_saving,
        child: ArDriveStandardModalNew(
          width: 500,
          title: strings.turboServicesTitle,
          content: SizedBox(
            width: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArDriveTextFieldNew(
                  controller: _uploadController,
                  isEnabled: !_saving,
                  hintText: 'https://upload.ardrive.io',
                  label: strings.turboUploadUrlLabel,
                  validator: _validateUrl,
                ),
                const SizedBox(height: ArDriveSpacing.md),
                ArDriveTextFieldNew(
                  controller: _paymentController,
                  isEnabled: !_saving,
                  hintText: 'https://payment.ardrive.io',
                  label: strings.turboPaymentUrlLabel,
                  validator: _validateUrl,
                ),
                if (_saveFailed) ...[
                  const SizedBox(height: ArDriveSpacing.md),
                  ArDriveNotice(
                    type: ArDriveNoticeType.error,
                    message: strings.settingsSaveFailed,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ModalAction.close(
              title: strings.cancel,
              isEnable: !_saving,
              action: () => Navigator.of(context).pop(),
            ),
            ModalAction(
              title: strings.save,
              isLoading: _saving,
              isEnable: _isValid && !_saving,
              action: () => _save(() => widget.onSave(
                    _uploadController.text.trim(),
                    _paymentController.text.trim(),
                  )),
            ),
          ],
        ));
  }
}
