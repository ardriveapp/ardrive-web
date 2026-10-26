import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArDriveDevToolOption', () {
    // The dev tools window calls every option through the raw type. An
    // option declared without one (`final x = ArDriveDevToolOption(...)`)
    // used to infer a `(String) => ...` callback, and calling it threw, so
    // "Switch ARIO to Devnet" and the Solana fields did nothing.
    test('an option declared without a type can be called through the raw type',
        () async {
      String? got;
      final switchToDevnet = ArDriveDevToolOption(
        name: 'Switch ARIO to Devnet',
        value: '',
        onChange: (value) async {
          got = value;
        },
        type: ArDriveDevToolOptionType.button,
      );
      final ArDriveDevToolOption asTheWindowSeesIt = switchToDevnet;

      asTheWindowSeesIt.onChange(asTheWindowSeesIt.value);

      expect(got, '');
    });

    test('a text option takes the submitted string', () {
      String? got;
      final rpcUrl = ArDriveDevToolOption(
        name: 'solanaRpcUrl',
        value: null as String?,
        onChange: (value) {
          got = value;
        },
        type: ArDriveDevToolOptionType.text,
      );
      final ArDriveDevToolOption asTheWindowSeesIt = rpcUrl;

      asTheWindowSeesIt.onChange('https://api.devnet.solana.com');

      expect(got, 'https://api.devnet.solana.com');
    });
  });
}
