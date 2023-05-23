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

class PresetAmountSelector extends StatefulWidget {
  final List<int> amounts;
  final String currencyUnit;
  final int preSelectedAmount;
  const PresetAmountSelector({
    super.key,
    required this.amounts,
    required this.currencyUnit,
    required this.preSelectedAmount,
  });

  @override
  State<PresetAmountSelector> createState() => _PresetAmountSelectorState();
}

class _PresetAmountSelectorState extends State<PresetAmountSelector> {
  final TextEditingController _customAmountController = TextEditingController();

  int selectedAmount = 0;

  @override
  void initState() {
    selectedAmount = widget.preSelectedAmount;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ButtonBar(
          children: widget.amounts
              .map((amount) => ArDriveButton(
                    backgroundColor:
                        selectedAmount == amount ? Colors.white : null,
                    style: ArDriveButtonStyle.secondary,
                    text: '$amount ${widget.currencyUnit}',
                    onPressed: () {
                      setState(() {
                        selectedAmount = amount;
                        _customAmountController.text = '';
                      });
                    },
                  ))
              .toList(),
        ),
        TextFormField(
          controller: _customAmountController,
          onChanged: (value) {
            setState(() {
              selectedAmount = int.tryParse(value) ?? 0;
            });
          },
        )
      ],
    );
  }
}

class BalanceView extends StatefulWidget {
  final BigInt balance;
  final int estimatedStorage;
  const BalanceView({
    super.key,
    required this.balance,
    required this.estimatedStorage,
  });

  @override
  State<BalanceView> createState() => _BalanceViewState();
}

class _BalanceViewState extends State<BalanceView> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: [
            const Text('Balance'),
            Text(widget.balance.toString()),
          ],
        ),
        Column(
          children: [
            const Text('Estimated Storage'),
            Text(widget.estimatedStorage.toString()),
          ],
        ),
      ],
    );
  }
}

class PriceEstimateView extends StatelessWidget {
  final double fiatAmount;
  final String fiatCurrency;
  final BigInt estimatedCredits; // in WC
  final int estimatedStorage; // in bytes
  const PriceEstimateView({
    super.key,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.estimatedCredits,
    required this.estimatedStorage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        Text(
          '$fiatCurrency $fiatAmount = $estimatedCredits credits = $estimatedStorage bytes',
        ),
        const Text('How are conversions determined?'),
        const Divider(),
      ],
    );
  }
}
