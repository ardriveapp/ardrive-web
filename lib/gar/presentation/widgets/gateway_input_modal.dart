import 'dart:async';

import 'package:ardrive/gar/presentation/widgets/gar_modal.dart';
import 'package:ardrive/gar/utils/gateway_validator.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';

class GatewayInputModal extends StatefulWidget {
  final String initialGateway;
  final Function(String) onSave;

  const GatewayInputModal({
    super.key,
    required this.initialGateway,
    required this.onSave,
  });

  @override
  State<GatewayInputModal> createState() => _GatewayInputModalState();
}

class _GatewayInputModalState extends State<GatewayInputModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _gatewayController;
  bool _isLoading = false;
  GatewayValidationResult? _validationResult;
  Timer? _debounce;
  String _lastValidatedText = '';

  @override
  void initState() {
    super.initState();
    _gatewayController = TextEditingController(text: widget.initialGateway);
    _lastValidatedText = widget.initialGateway;
    _gatewayController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _gatewayController.removeListener(_onTextChanged);
    _gatewayController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final currentText = _gatewayController.text.trim();
    if (currentText != _lastValidatedText) {
      _validateGateway();
    }
  }

  Future<void> _validateGateway() async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final gateway = _gatewayController.text.trim();

      if (gateway == _lastValidatedText) return;

      _lastValidatedText = gateway;

      if (gateway.isEmpty) {
        setState(() {
          _validationResult = null;
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = true);

      try {
        final validationResult =
            await GatewayValidator.validateGateway(gateway);

        if (mounted) {
          setState(() {
            _validationResult = validationResult;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _validationResult = const GatewayValidationResult(
              isValid: false,
              isActive: false,
              isArweaveGateway: false,
              message: 'Error validating gateway',
            );
            _isLoading = false;
          });
        }
      }
    });
  }

  Future<void> _selectFromArIOGateways() async {
    final selectedGateway = await showArIOGatewaySelectorModal(context);
    if (selectedGateway != null) {
      final gatewayUrl = 'https://${selectedGateway.settings.fqdn}';

      // Update the controller using value to ensure the text field updates
      _gatewayController.value = _gatewayController.value.copyWith(
        text: gatewayUrl,
        selection: TextSelection.collapsed(offset: gatewayUrl.length),
      );

      // Reset the last validated text to ensure validation runs
      _lastValidatedText = '';

      // Manually trigger the text change handler
      _onTextChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      width: 500,
      title: 'Switch Gateway',
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter a custom gateway URL or select from AR.IO gateways.',
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: 16),
            ArDriveTextFieldNew(
              controller: _gatewayController,
              label: 'Gateway URL',
              hintText: defaultGraphqlGateway,
              suffixIcon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _validationResult != null
                      ? _buildValidationIcon()
                      : null,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a gateway URL';
                }
                if (_validationResult != null && !_validationResult!.isValid) {
                  return _validationResult!.message;
                }
                return null;
              },
            ),
            if (_validationResult != null) ...[
              const SizedBox(height: 8),
              _buildValidationMessage(),
            ],
            const SizedBox(height: 24),
            if (isArioSDKSupportedOnPlatform()) ...[
              Center(
                child: ArDriveButtonNew(
                  typography: typography,
                  text: 'Select AR.IO Gateway',
                  variant: ButtonVariant.primary,
                  onPressed: _selectFromArIOGateways,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: 'Cancel',
        ),
        ModalAction(
          action: _validationResult?.canBeUsed == true
              ? () {
                  if (_formKey.currentState!.validate()) {
                    final cleanedUrl =
                        GatewayValidator.cleanUrl(_gatewayController.text);
                    widget.onSave(cleanedUrl);
                    Navigator.of(context).pop();
                  }
                }
              : () {},
          title: 'Save',
        ),
      ],
    );
  }

  Widget _buildValidationIcon() {
    switch (_validationResult!.warningLevel) {
      case GatewayWarningLevel.none:
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 20,
        );
      case GatewayWarningLevel.warning:
        return const Icon(
          Icons.warning,
          color: Colors.orange,
          size: 20,
        );
      case GatewayWarningLevel.error:
        return const Icon(
          Icons.error,
          color: Colors.red,
          size: 20,
        );
    }
  }

  Widget _buildValidationMessage() {
    final validationResult = _validationResult!;
    Color messageColor;
    IconData icon;

    switch (validationResult.warningLevel) {
      case GatewayWarningLevel.none:
        messageColor = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case GatewayWarningLevel.warning:
        messageColor = Colors.orange;
        icon = Icons.warning_outlined;
        break;
      case GatewayWarningLevel.error:
        messageColor = Colors.red;
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: messageColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: messageColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: messageColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              validationResult.message,
              style: ArDriveTypographyNew.of(context).paragraphSmall(
                color: messageColor,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showGatewayInputModal(
  BuildContext context, {
  required String initialGateway,
  required Function(String) onSave,
}) {
  return showArDriveDialog(
    context,
    content: GatewayInputModal(
      initialGateway: initialGateway,
      onSave: onSave,
    ),
  );
}
