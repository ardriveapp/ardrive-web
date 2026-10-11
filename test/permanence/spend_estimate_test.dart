import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> topUp(String type, int winc, {String? giftMessage}) => {
        'type': type,
        'wincCredited': '$winc',
        if (giftMessage != null) 'giftMessage': giftMessage,
      };

  test('credits used are everything credited minus what is left', () {
    expect(
      creditsUsed(
        payments: [topUp('fiat', 1000), topUp('crypto', 500)],
        balanceWinc: BigInt.from(300),
      ),
      BigInt.from(1200),
    );
  });

  test('granted and gifted credits count like bought ones', () {
    // What the console calls "Credit grant via admin", and a gift: credits
    // all the same, spent the same way.
    expect(
      creditsUsed(
        payments: [
          topUp('fiat', 5000),
          topUp('fiat', 400, giftMessage: 'happy birthday'),
        ],
        balanceWinc: BigInt.from(100),
      ),
      BigInt.from(5300),
    );
  });

  test('a balance above what came in is nothing used, not less than nothing',
      () {
    // Credits shared to this wallet sit in its balance with no top-up.
    expect(
      creditsUsed(
        payments: [topUp('fiat', 1000)],
        balanceWinc: BigInt.from(5000),
      ),
      BigInt.zero,
    );
  });

  test('a row it cannot read adds nothing', () {
    expect(
      creditsUsed(
        payments: [
          topUp('fiat', 1000),
          {'type': 'fiat', 'wincCredited': 'not a number'},
        ],
        balanceWinc: BigInt.zero,
      ),
      BigInt.from(1000),
    );
  });
}
