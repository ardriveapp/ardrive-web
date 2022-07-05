import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/launch_inferno_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('testing getUrlForCurrentLocalization function', () {
    test('should return the zh rules page for zh locale', () {
      expect(Resources.infernoRulesLinkZh, getUrlForCurrentLocalization('zh'));
    });
    test('should return the en rules page for zh locale', () {
      expect(Resources.infernoRulesLinkEn, getUrlForCurrentLocalization('en'));
    });

    test(
        'should return the en rules page for other localizations different of en and zh',
        () {
      expect(Resources.infernoRulesLinkEn, getUrlForCurrentLocalization('es'));
    });
  });
}
