import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/inferno_rules_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('testing getInfernoUrlForCurrentLocalization function', () {
    test('should return the zh rules page for zh locale', () {
      expect(Resources.infernoRulesLinkZh,
          getInfernoUrlForCurrentLocalization('zh'));
    });
    test('should return the en rules page for zh locale', () {
      expect(Resources.infernoRulesLinkEn,
          getInfernoUrlForCurrentLocalization('en'));
    });

    test(
        'should return the en rules page for other localizations different of en and zh',
        () {
      expect(Resources.infernoRulesLinkEn,
          getInfernoUrlForCurrentLocalization('es'));
    });
  });
}
