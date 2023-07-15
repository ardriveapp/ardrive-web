import 'package:ardrive/cookie_policy_consent/cookie_policy_consent.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLocalKeyValueStore extends Mock implements LocalKeyValueStore {}

void main() {
  group('ArDriveCookiePolicyConsent', () {
    late LocalKeyValueStore store;
    late ArDriveCookiePolicyConsent consent;

    setUp(() {
      store = MockLocalKeyValueStore();
      consent = ArDriveCookiePolicyConsent(store);
      // Register the store for verification in mocktail.
      when(() => store.getBool(any())).thenReturn(false);
    });

    test('should return false when user has not accepted cookie policy',
        () async {
      when(() => store.getBool(any())).thenReturn(false);
      expect(await consent.hasAcceptedCookiePolicy(), isFalse);
    });

    test('should return true when user has accepted cookie policy', () async {
      when(() => store.getBool(any())).thenReturn(true);
      expect(await consent.hasAcceptedCookiePolicy(), isTrue);
    });

    test(
        'should set cookie policy as accepted when acceptCookiePolicy is called',
        () async {
      when(() => store.putBool(hasAcceptedCookiePolicyKey, true))
          .thenAnswer((invocation) => Future.value(true));

      await consent.acceptCookiePolicy();

      verify(() => store.putBool(hasAcceptedCookiePolicyKey, true)).called(1);
    });
  });
}
