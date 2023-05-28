import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/turbo_payment/file_size_units.dart';
import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TopUpDialog extends StatefulWidget {
  const TopUpDialog({super.key});

  @override
  State<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<TopUpDialog> {
  late PaymentBloc paymentBloc;
  late Wallet wallet;

  @override
  initState() {
    wallet = (context.read<ProfileCubit>().state as ProfileLoggedIn).wallet;
    paymentBloc = PaymentBloc(
      paymentService: context.read<PaymentService>(),
      wallet: wallet,
    )..add(LoadInitialData());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      width: 575,
      content: BlocBuilder<PaymentBloc, PaymentState>(
        bloc: paymentBloc,
        builder: (context, state) {
          if (state is PaymentLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is PaymentLoaded) {
            return Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SvgPicture.asset(
                      Resources.images.brand.turbo,
                      height: 30,
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
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
                  balance: state.balance,
                  estimatedStorage: state.estimatedStorageForBalance,
                ),
                const SizedBox(height: 16),
                const PresetAmountSelector(
                  amounts: [25, 50, 75, 100],
                  currencyUnit: '\$',
                  preSelectedAmount: 25,
                ),
                const SizedBox(height: 16),
                PriceEstimateView(
                  fiatAmount: state.selectedAmount.toInt(),
                  fiatCurrency: '\$',
                  estimatedCredits: state.creditsForSelectedAmount,
                  estimatedStorage: state.estimatedStorageForSelectedAmount,
                  storageUnit: paymentBloc.currentDataUnit.name,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          DropdownMenu(
                            label: const Text('Currency'),
                            hintText: 'Currency',
                            initialSelection: paymentBloc.currentCurrency,
                            dropdownMenuEntries: [
                              DropdownMenuEntry(
                                label: paymentBloc.currentCurrency,
                                value: paymentBloc.currentCurrency,
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          DropdownMenu(
                            label: Text('Units'),
                            hintText: 'Units',
                            initialSelection: paymentBloc.currentDataUnit,
                            onSelected: (value) {
                              paymentBloc.add(
                                DataUnitChanged(value as FileSizeUnit),
                              );
                            },
                            dropdownMenuEntries: [
                              ...FileSizeUnit.values.map(
                                (unit) => DropdownMenuEntry(
                                  label: unit.name,
                                  value: unit,
                                  style: ButtonStyle(
                                    foregroundColor:
                                        MaterialStateColor.resolveWith(
                                      (states) => ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault,
                                    ),
                                  ),
                                ),
                              )
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
            );
          } else if (state is PaymentError) {
            return Center(child: Text(appLocalizationsOf(context).error));
          }
          return const SizedBox();
        },
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
  final String estimatedStorage;
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
            Text(widget.estimatedStorage),
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
  final String estimatedStorage;
  final String storageUnit;
  const PriceEstimateView({
    super.key,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.estimatedCredits,
    required this.estimatedStorage,
    required this.storageUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          '$fiatCurrency $fiatAmount = $estimatedCredits credits = $estimatedStorage $storageUnit',
        ),
        const SizedBox(height: 16),
        const Text('How are conversions determined?'),
        const Divider(),
      ],
    );
  }
}
