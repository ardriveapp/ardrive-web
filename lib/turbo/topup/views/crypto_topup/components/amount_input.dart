import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Input field for entering payment amount
class CryptoAmountInput extends StatefulWidget {
  final CryptoToken token;
  final bool isUsdMode;
  final double? currentAmount;
  final TokenBalance? balance;
  final bool isLoading;
  final String? error;
  final ValueChanged<double> onAmountChanged;
  final VoidCallback? onToggleMode;

  const CryptoAmountInput({
    super.key,
    required this.token,
    required this.isUsdMode,
    this.currentAmount,
    this.balance,
    this.isLoading = false,
    this.error,
    required this.onAmountChanged,
    this.onToggleMode,
  });

  @override
  State<CryptoAmountInput> createState() => _CryptoAmountInputState();
}

class _CryptoAmountInputState extends State<CryptoAmountInput> {
  late TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentAmount?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(CryptoAmountInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if the amount changed externally
    if (widget.currentAmount != oldWidget.currentAmount &&
        widget.currentAmount?.toString() != _controller.text) {
      _controller.text = widget.currentAmount?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input container
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorTokens.containerL1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.error != null
                  ? colorTokens.strokeLow
                  : colorTokens.strokeLow,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Currency symbol/prefix
                  Text(
                    widget.isUsdMode ? '\$' : widget.token.symbol,
                    style: typography.heading4(
                      fontWeight: ArFontWeight.bold,
                      color: colorTokens.textMid,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Amount input
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: typography.heading3(
                        fontWeight: ArFontWeight.bold,
                        color: colorTokens.textHigh,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '0.00',
                        hintStyle: typography.heading3(
                          fontWeight: ArFontWeight.bold,
                          color: colorTokens.textLow,
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,8}$'),
                        ),
                      ],
                      onChanged: (value) {
                        final amount = double.tryParse(value) ?? 0;
                        widget.onAmountChanged(amount);
                      },
                    ),
                  ),
                  // Toggle mode button
                  if (widget.onToggleMode != null)
                    GestureDetector(
                      onTap: widget.onToggleMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorTokens.containerL2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.isUsdMode ? 'USD' : widget.token.symbol,
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                            color: colorTokens.textMid,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Balance display
              if (widget.balance != null) ...[
                const SizedBox(height: 8),
                if (widget.balance!.hasError)
                  // Show error message (e.g., "Please switch to Base")
                  Row(
                    children: [
                      Icon(
                        widget.balance!.isNetworkError
                            ? Icons.swap_horiz
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: colorTokens.textLow,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.balance!.error!,
                          style: typography.paragraphSmall(
                            color: colorTokens.textLow,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  // Show balance with MAX button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Balance: ${widget.balance!.displayBalance}',
                        style: typography.paragraphSmall(
                          color: colorTokens.textMid,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _setMaxAmount(),
                        child: Text(
                          'MAX',
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                            color: colorTokens.textHigh,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        // Error message
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.error!,
            style: typography.paragraphSmall(
              color: colorTokens.textLow,
            ),
          ),
        ],
      ],
    );
  }

  void _setMaxAmount() {
    if (widget.balance == null) return;

    // Use USD value when in USD mode, otherwise use token balance
    final double maxAmount;
    if (widget.isUsdMode && widget.balance!.usdValue != null) {
      maxAmount = widget.balance!.usdValue!;
    } else {
      maxAmount = widget.balance!.balance;
    }

    _controller.text = maxAmount.toString();
    widget.onAmountChanged(maxAmount);
  }
}

/// Preset amount buttons for quick selection
class PresetAmountButtons extends StatelessWidget {
  final List<double> amounts;
  final double? selectedAmount;
  final bool isUsdMode;
  final ValueChanged<double> onAmountSelected;

  const PresetAmountButtons({
    super.key,
    this.amounts = const [10, 25, 50, 100],
    this.selectedAmount,
    this.isUsdMode = true,
    required this.onAmountSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: amounts.map((amount) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: amounts.last != amount ? 8 : 0,
            ),
            child: _PresetAmountButton(
              amount: amount,
              isUsdMode: isUsdMode,
              isSelected: selectedAmount == amount,
              onTap: () => onAmountSelected(amount),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PresetAmountButton extends StatelessWidget {
  final double amount;
  final bool isUsdMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetAmountButton({
    required this.amount,
    required this.isUsdMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorTokens.containerL3 : colorTokens.containerL1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorTokens.strokeHigh : colorTokens.strokeLow,
          ),
        ),
        child: Center(
          child: Text(
            isUsdMode ? '\$${amount.toStringAsFixed(0)}' : amount.toString(),
            style: typography.paragraphNormal(
              fontWeight:
                  isSelected ? ArFontWeight.semiBold : ArFontWeight.book,
              color: isSelected ? colorTokens.textHigh : colorTokens.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

/// Promo code input field
class PromoCodeInput extends StatefulWidget {
  final String? currentCode;
  final bool isValidating;
  final bool isValid;
  final String? error;
  final ValueChanged<String> onCodeSubmitted;
  final VoidCallback? onClear;

  const PromoCodeInput({
    super.key,
    this.currentCode,
    this.isValidating = false,
    this.isValid = false,
    this.error,
    required this.onCodeSubmitted,
    this.onClear,
  });

  @override
  State<PromoCodeInput> createState() => _PromoCodeInputState();
}

class _PromoCodeInputState extends State<PromoCodeInput> {
  late TextEditingController _controller;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCode ?? '');
    _isExpanded = widget.currentCode != null && widget.currentCode!.isNotEmpty;
  }

  @override
  void didUpdateWidget(PromoCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to external changes of currentCode
    if (oldWidget.currentCode != widget.currentCode) {
      _controller.text = widget.currentCode ?? '';
      setState(() {
        _isExpanded =
            widget.currentCode != null && widget.currentCode!.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    if (!_isExpanded) {
      return GestureDetector(
        onTap: () => setState(() => _isExpanded = true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer,
              size: 14,
              color: colorTokens.textMid,
            ),
            const SizedBox(width: 4),
            Text(
              'Have a promo code?',
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.error != null
              ? colorTokens.strokeLow
              : widget.isValid
                  ? colorTokens.strokeHigh
                  : colorTokens.strokeLow,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: typography.paragraphNormal(
                    color: colorTokens.textHigh,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter promo code',
                    hintStyle: typography.paragraphNormal(
                      color: colorTokens.textLow,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  enabled: !widget.isValid,
                  onSubmitted: widget.onCodeSubmitted,
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isValidating)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorTokens.textMid,
                  ),
                )
              else if (widget.isValid)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: colorTokens.textHigh,
                    ),
                    if (widget.onClear != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          _controller.clear();
                          widget.onClear?.call();
                        },
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: colorTokens.textMid,
                        ),
                      ),
                    ],
                  ],
                )
              else
                GestureDetector(
                  onTap: () => widget.onCodeSubmitted(_controller.text),
                  child: Text(
                    'Apply',
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ),
            ],
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.error!,
              style: typography.paragraphSmall(
                color: colorTokens.textLow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
