import 'package:ardrive/cookie_policy_consent/blocs/cookie_policy_consent_bloc.dart';
import 'package:ardrive/cookie_policy_consent/cookie_policy_consent.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCookiePolicyConsent extends Mock
    implements ArDriveCookiePolicyConsent {}

void main() {
  late ArDriveCookiePolicyConsent mockCookiePolicyConsent;
  late CookiePolicyConsentBloc cookiePolicyConsentBloc;

  setUp(() {
    mockCookiePolicyConsent = MockCookiePolicyConsent();
    cookiePolicyConsentBloc = CookiePolicyConsentBloc(mockCookiePolicyConsent);
  });

  test('Initial state is CookiePolicyConsentInitial', () {
    expect(cookiePolicyConsentBloc.state, CookiePolicyConsentInitial());
  });

  blocTest<CookiePolicyConsentBloc, CookiePolicyConsentState>(
    'emits [VerifyingCookieConsent, CookiePolicyConsentAccepted] when VerifyCookiePolicyConsent added and consent was already accepted',
    build: () {
      when(() => mockCookiePolicyConsent.hasAcceptedCookiePolicy())
          .thenAnswer((_) async => true);
      return cookiePolicyConsentBloc;
    },
    act: (bloc) => bloc.add(VerifyCookiePolicyConsent()),
    expect: () => [VerifyingCookieConsent(), CookiePolicyConsentAccepted()],
  );

  blocTest<CookiePolicyConsentBloc, CookiePolicyConsentState>(
    'emits [VerifyingCookieConsent, CookiePolicyConsentRejected] when VerifyCookiePolicyConsent added and consent was not accepted',
    build: () {
      when(() => mockCookiePolicyConsent.hasAcceptedCookiePolicy())
          .thenAnswer((_) async => false);
      return cookiePolicyConsentBloc;
    },
    act: (bloc) => bloc.add(VerifyCookiePolicyConsent()),
    expect: () => [VerifyingCookieConsent(), CookiePolicyConsentRejected()],
  );

  blocTest<CookiePolicyConsentBloc, CookiePolicyConsentState>(
    'emits [CookiePolicyConsentAccepted] when AcceptCookiePolicyConsent added',
    build: () => cookiePolicyConsentBloc,
    setUp: () {
      when(() => mockCookiePolicyConsent.acceptCookiePolicy()).thenAnswer(
        (_) async {},
      );
    },
    act: (bloc) {
      bloc.add(AcceptCookiePolicyConsent());
    },
    verify: (_) {
      verify(() => mockCookiePolicyConsent.acceptCookiePolicy()).called(1);
    },
    expect: () => [CookiePolicyConsentAccepted()],
  );
}
