import 'dart:async';

import 'package:ardrive/gar/presentation/widgets/gar_modal.dart';
import 'package:ardrive/gar/utils/gateway_validator.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';

class GatewayInputModal extends StatefulWidget {
  final String initialGateway;
  final Function(String) onSave;

  /// Checks a gateway URL. Replaced in tests.
  final Future<GatewayValidationResult> Function(String url) validate;

  const GatewayInputModal({
    super.key,
    required this.initialGateway,
    required this.onSave,
    this.validate = GatewayValidator.validateGateway,
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
      // The last check was for other text: drop it, so Save can't save this
      // text on the strength of it while the new check waits to run.
      if (_validationResult != null) setState(() => _validationResult = null);
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

      // A result is for the URL it checked. One that comes back after the
      // text changed is dropped: kept, it could enable Save for a URL
      // nobody checked.
      bool isCurrent() => mounted && _gatewayController.text.trim() == gateway;

      try {
        final validationResult = await widget.validate(gateway);

        if (isCurrent()) {
          setState(() {
            _validationResult = validationResult;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (isCurrent()) {
          setState(() {
            _validationResult = GatewayValidationResult(
              isValid: false,
              isActive: false,
              isArweaveGateway: false,
              message: appLocalizationsOf(context).gatewayCheckFailed,
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
    final strings = appLocalizationsOf(context);
    final canSave = !_isLoading && _validationResult?.canBeUsed == true;

    return ArDriveStandardModalNew(
      width: 500,
      title: strings.gatewaySwitchTitle,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.gatewaySwitchDescription,
              style: typography.paragraphNormal(color: colorTokens.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            ArDriveTextFieldNew(
              controller: _gatewayController,
              label: strings.gatewayUrlLabel,
              hintText: defaultGraphqlGateway,
              suffixIcon: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(ArDriveSpacing.sm),
                      child: ArDriveSpinner(),
                    )
                  : _validationResult != null
                      ? _buildValidationIcon(colorTokens)
                      : null,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return strings.gatewayUrlRequired;
                }
                if (_validationResult != null && !_validationResult!.isValid) {
                  return _validationResult!.message;
                }
                return null;
              },
            ),
            if (_validationResult != null) ...[
              const SizedBox(height: ArDriveSpacing.xs),
              ArDriveNotice(
                type: _noticeType(_validationResult!.warningLevel),
                message: _validationResult!.message,
              ),
            ],
            if (isArioSDKSupportedOnPlatform()) ...[
              const SizedBox(height: ArDriveSpacing.lg),
              ArDriveButtonNew(
                maxWidth: double.infinity,
                typography: typography,
                text: strings.gatewayChooseArio,
                variant: ButtonVariant.secondary,
                onPressed: _selectFromArIOGateways,
              ),
            ],
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: strings.cancel,
        ),
        // Only once the gateway has been checked and can be used. It looked
        // ready before that and did nothing when pressed.
        ModalAction(
          isEnable: canSave,
          action: () {
            if (!canSave || !_formKey.currentState!.validate()) return;
            widget.onSave(GatewayValidator.cleanUrl(_gatewayController.text));
            Navigator.of(context).pop();
          },
          title: strings.save,
        ),
      ],
    );
  }

  static ArDriveNoticeType _noticeType(GatewayWarningLevel level) =>
      switch (level) {
        GatewayWarningLevel.none => ArDriveNoticeType.success,
        GatewayWarningLevel.warning => ArDriveNoticeType.warning,
        GatewayWarningLevel.error => ArDriveNoticeType.error,
      };

  Widget _buildValidationIcon(ArDriveColorTokens colorTokens) {
    final (icon, color) = switch (_validationResult!.warningLevel) {
      GatewayWarningLevel.none => (
          Icons.check_circle,
          colorTokens.statusSuccessFg
        ),
      GatewayWarningLevel.warning => (
          Icons.warning,
          colorTokens.statusWarningFg
        ),
      GatewayWarningLevel.error => (Icons.error, colorTokens.statusErrorFg),
    };
    return Icon(icon, color: color, size: 20);
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
