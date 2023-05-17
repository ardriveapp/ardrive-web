import 'package:alchemist/alchemist.dart';
import 'package:ardrive/components/turbo_balance_widget.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPaymentService extends Mock implements PaymentService {}

void main() async {
  final mockPaymentService = MockPaymentService();
  final wallet = await Wallet.generate();
  group('Turbo Balance Widget', () {
    when(() => mockPaymentService.getBalance(wallet: wallet))
        .thenAnswer((_) async => BigInt.from(1000000000000));
    goldenTest(
      'renders correctly',
      fileName: 'turbo_balance_widget',
      builder: () {
        return GoldenTestGroup(
          scenarioConstraints: const BoxConstraints(maxWidth: 600),
          children: [
            GoldenTestScenario(
              name: 'with balance',
              child: ArDriveTheme(
                child: TurboBalance(
                  paymentService: mockPaymentService,
                  wallet: wallet,
                ),
              ),
            ),
          ],
        );
      },
    );
  });
}
