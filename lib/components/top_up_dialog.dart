import 'package:ardrive/misc/resources.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TopUpDialog extends StatefulWidget {
  const TopUpDialog({super.key});

  @override
  State<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<TopUpDialog> {
  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      width: 575,
      content: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SvgPicture.asset(
                Resources.images.brand.turbo,
                height: 30,
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                colorBlendMode: BlendMode.srcIn,
                fit: BoxFit.contain,
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
              )
            ],
          ),
          const SizedBox(height: 16),
          BalanceView(
            balance: BigInt.from(1000000000000000000),
            estimatedStorage: 1000000000,
          ),
          const SizedBox(height: 16),
          const PresetAmountSelector(
            amounts: [25, 50, 75, 100],
            currencyUnit: '\$',
            preSelectedAmount: 25,
          ),
          const SizedBox(height: 16),
          PriceEstimateView(
            fiatAmount: 25,
            fiatCurrency: '\$',
            estimatedCredits: BigInt.from(100),
            estimatedStorage: 1024,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    DropdownMenu(
                      label: Text('Currency'),
                      hintText: 'Currency',
                      dropdownMenuEntries: [
                        DropdownMenuEntry(label: 'USD', value: 'USD'),
                      ],
                    ),
                    SizedBox(width: 8),
                    DropdownMenu(
                      label: Text('Units'),
                      hintText: 'Units',
                      dropdownMenuEntries: [
                        DropdownMenuEntry(label: 'KB', value: 'KB'),
                        DropdownMenuEntry(label: 'MB', value: 'MB'),
                        DropdownMenuEntry(label: 'GB', value: 'GB'),
                      ],
                    ),
                  ],
                ),
              ),
              ArDriveButton(
                text: 'Next',
                onPressed: () {},
              ),
            ],
          )
        ],
      ),
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
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Buy Credits'),
        const SizedBox(height: 8),
        const Text('Choose an amount'),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.max,
          children: widget.amounts
              .map(
                (amount) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ArDriveButton(
                    backgroundColor:
                        selectedAmount == amount ? Colors.white : null,
                    style: ArDriveButtonStyle.secondary,
                    maxHeight: 40,
                    maxWidth: 112,
                    fontStyle: ArDriveTypography.body.captionRegular().copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                        ),
                    text: '$amount ${widget.currencyUnit}',
                    onPressed: () {
                      setState(() {
                        selectedAmount = amount;
                        _customAmountController.text = '';
                      });
                    },
                  ),
                ),
              )
              .toList(),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Or chose a custom amount'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          width: 112,
          height: 40,
          child: TextFormField(
            expands: false,
            controller: _customAmountController,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onChanged: (value) {
              setState(() {
                selectedAmount = int.tryParse(value) ?? 0;
              });
            },
          ),
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
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Balance'),
            Text(widget.balance.toString()),
          ],
        ),
        const SizedBox(
          width: 32,
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
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
  final int fiatAmount;
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          '$fiatCurrency $fiatAmount = $estimatedCredits credits = $estimatedStorage bytes',
        ),
        const SizedBox(height: 16),
        const Text('How are conversions determined?'),
        const Divider(),
      ],
    );
  }
}
