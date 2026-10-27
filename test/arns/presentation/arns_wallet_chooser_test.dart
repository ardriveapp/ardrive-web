import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_chooser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('walletBrowseTarget', () {
    // A shared private drive link keeps its key in the address bar.
    final base = Uri.parse(
      'https://app.ardrive.io/#/drives/abc?name=Docs&driveKey=SECRET',
    );

    test('sends a wallet browser only the origin on the web', () {
      final target = walletBrowseTarget(base, isWeb: true);

      expect(target, 'https://app.ardrive.io');
      expect(phantomBrowseUrl(target), isNot(contains('SECRET')));
      expect(solflareBrowseUrl(target), isNot(contains('SECRET')));
    });

    test('keeps the app address off the web', () {
      expect(walletBrowseTarget(base, isWeb: false), 'https://app.ardrive.io');
    });
  });
}
