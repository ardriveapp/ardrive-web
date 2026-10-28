import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Default USD presets for card payments: $10, $25, $50, $100, $250
const List<int> defaultFiatPresets = [10, 25, 50, 100, 250];

/// Token-specific presets based on the Turbo app (5 presets each to match USD)
Map<CryptoToken, List<double>> tokenPresets = {
  CryptoToken.arioAO: [10, 50, 100, 500, 1000],
  CryptoToken.arioAOViaEth: [10, 50, 100, 500, 1000],
  CryptoToken.arioBase: [10, 50, 100, 500, 1000],
  CryptoToken.ethL1: [0.01, 0.025, 0.05, 0.1, 0.25],
  CryptoToken.ethBase: [0.01, 0.025, 0.05, 0.1, 0.25],
  CryptoToken.sol: [0.05, 0.1, 0.25, 0.5, 1.0],
  CryptoToken.usdcBase: [10, 25, 50, 100, 250],
  CryptoToken.usdcEth: [10, 25, 50, 100, 250],
};

/// Minimum and maximum amounts for card payments (USD)
const int minFiatAmount = 5;
const int maxFiatAmount = 10000;

/// Selector for fiat/currency-based amount selection.
///
/// Shows preset amounts and a custom amount input.
/// Can be used for USD (card payments) or token amounts (crypto payments).
class FiatPresetSelector extends StatefulWidget {
  /// Preset amounts to display
  final List<double> presets;

  /// Currently selected preset (null if custom amount is selected)
  final double? selectedPreset;

  /// Custom amount value
  final double? customValue;

  /// Currency symbol or token symbol to display
  final String currencySymbol;

  /// Whether this is for token amounts (affects formatting)
  final bool isTokenAmount;

  /// Callback when a preset is selected
  final ValueChanged<double> onPresetSelected;

  /// Callback when custom amount changes
  final ValueChanged<double> onCustomAmountChanged;

  const FiatPresetSelector({
    super.key,
    this.presets = const [],
    this.selectedPreset,
    this.customValue,
    this.currencySymbol = '\$',
    this.isTokenAmount = false,
    required this.onPresetSelected,
    required this.onCustomAmountChanged,
  });

  /// Creates a selector for USD card payments
  factory FiatPresetSelector.usd({
    Key? key,
    double? selectedPreset,
    double? customValue,
    required ValueChanged<double> onPresetSelected,
    required ValueChanged<double> onCustomAmountChanged,
  }) {
    return FiatPresetSelector(
      key: key,
      presets: defaultFiatPresets.map((e) => e.toDouble()).toList(),
      selectedPreset: selectedPreset,
      customValue: customValue,
      currencySymbol: '\$',
      isTokenAmount: false,
      onPresetSelected: onPresetSelected,
      onCustomAmountChanged: onCustomAmountChanged,
    );
  }

  /// Creates a selector for crypto token amounts
  factory FiatPresetSelector.token({
    Key? key,
    required CryptoToken token,
    double? selectedPreset,
    double? customValue,
    required ValueChanged<double> onPresetSelected,
    required ValueChanged<double> onCustomAmountChanged,
  }) {
    return FiatPresetSelector(
      key: key,
      presets: tokenPresets[token] ?? [0.1, 0.5, 1, 5],
      selectedPreset: selectedPreset,
      customValue: customValue,
      currencySymbol: token.symbol,
      isTokenAmount: true,
      onPresetSelected: onPresetSelected,
      onCustomAmountChanged: onCustomAmountChanged,
    );
  }

  @override
  State<FiatPresetSelector> createState() => _FiatPresetSelectorState();
}

class _FiatPresetSelectorState extends State<FiatPresetSelector> {
  final TextEditingController _customAmountController = TextEditingController();
  final FocusNode _customAmountFocus = FocusNode();
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    if (widget.customValue != null && widget.customValue! > 0) {
      _customAmountController.text = _formatValue(widget.customValue!);
    }
  }

  @override
  void didUpdateWidget(FiatPresetSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear custom input when a preset is selected
    if (widget.selectedPreset != null && oldWidget.selectedPreset == null) {
      _customAmountController.clear();
      _validationMessage = null;
    }
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    _customAmountFocus.dispose();
    super.dispose();
  }

  String _formatValue(double value) {
    if (widget.isTokenAmount) {
      // For tokens, show decimal places as needed
      if (value == value.roundToDouble()) {
        return value.toInt().toString();
      }
      return value.toString();
    } else {
      // For USD, show as integer
      return value.toInt().toString();
    }
  }

  String _formatDisplayValue(double value) {
    if (widget.isTokenAmount) {
      final formatted = _formatValue(value);
      return '$formatted ${widget.currencySymbol}';
    } else {
      final formatted = NumberFormat('#,##0').format(value.toInt());
      return '${widget.currencySymbol}$formatted';
    }
  }

  void _onPresetSelected(double preset) {
    _customAmountController.clear();
    setState(() {
      _validationMessage = null;
    });
    widget.onPresetSelected(preset);
  }

  void _onCustomAmountChanged(String value) {
    final numValue = double.tryParse(value.replaceAll(',', ''));
    if (value.isEmpty) {
      setState(() {
        _validationMessage = null;
      });
      // Notify parent that the custom amount was cleared (0 disables checkout)
      widget.onCustomAmountChanged(0);
      return;
    }

    if (numValue == null || numValue <= 0) {
      setState(() {
        _validationMessage = 'Please enter a valid amount';
      });
      return;
    }

    if (!widget.isTokenAmount) {
      // Validate USD range
      if (numValue < minFiatAmount || numValue > maxFiatAmount) {
        setState(() {
          _validationMessage =
              'Please enter an amount between \$${NumberFormat('#,##0').format(minFiatAmount)} and \$${NumberFormat('#,##0').format(maxFiatAmount)}';
        });
        return;
      }
    }

    setState(() {
      _validationMessage = null;
    });

    widget.onCustomAmountChanged(numValue);
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isTokenAmount ? 'Token amount' : 'Amount',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        // Preset buttons
        _buildPresetGrid(context),
        const SizedBox(height: 16),
        // Custom amount section
        _buildCustomAmountSection(context),
      ],
    );
  }

  Widget _buildPresetGrid(BuildContext context) {
    // None is chosen while a custom amount is in use.
    return ArDriveSegmentedControl<double>(
      expand: true,
      selected: widget.selectedPreset,
      onSelected: _onPresetSelected,
      segments: [
        for (final preset in widget.presets)
          ArDriveSegment(value: preset, label: _formatDisplayValue(preset)),
      ],
    );
  }

  Widget _buildCustomAmountSection(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final labelText = widget.isTokenAmount
        ? 'Or enter custom ${widget.currencySymbol} amount'
        : 'Or enter custom amount (\$${NumberFormat('#,##0').format(minFiatAmount)} - \$${NumberFormat('#,##0').format(maxFiatAmount)})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: typography.paragraphSmall(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textMid,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 160,
          child: _CustomAmountTextField(
            controller: _customAmountController,
            focusNode: _customAmountFocus,
            prefix: widget.isTokenAmount ? null : widget.currencySymbol,
            suffix: widget.isTokenAmount ? widget.currencySymbol : null,
            onChanged: _onCustomAmountChanged,
            allowDecimals: widget.isTokenAmount,
          ),
        ),
        if (_validationMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _validationMessage!,
            style: typography.paragraphSmall(
              color: colors.statusErrorFg,
            ),
          ),
        ],
      ],
    );
  }
}

/// The custom amount, on the standard text field.
class _CustomAmountTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? prefix;
  final String? suffix;
  final ValueChanged<String> onChanged;
  final bool allowDecimals;

  const _CustomAmountTextField({
    required this.controller,
    required this.focusNode,
    this.prefix,
    this.suffix,
    required this.onChanged,
    this.allowDecimals = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final prefix = this.prefix;
    final suffix = this.suffix;

    return ArDriveTextFieldNew(
      controller: controller,
      focusNode: focusNode,
      hintText: '0',
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimals),
      inputFormatters: [
        if (allowDecimals)
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      prefix: prefix == null
          ? null
          : Text(
              '$prefix ',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colors.textHigh,
              ),
            ),
      suffixIcon: suffix == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  suffix,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textMid,
                  ),
                ),
              ),
            ),
      onChanged: onChanged,
    );
  }
}
