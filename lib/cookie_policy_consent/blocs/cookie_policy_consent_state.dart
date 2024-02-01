part of 'cookie_policy_consent_bloc.dart';

abstract class CookiePolicyConsentState extends Equatable {
  const CookiePolicyConsentState();

  @override
  List<Object> get props => [];
}

class CookiePolicyConsentInitial extends CookiePolicyConsentState {}

class VerifyingCookieConsent extends CookiePolicyConsentState {
  @override
  List<Object> get props => [];
}

class CookiePolicyConsentAccepted extends CookiePolicyConsentState {
  @override
  List<Object> get props => [];
}

class CookiePolicyConsentRejected extends CookiePolicyConsentState {
  @override
  List<Object> get props => [];
}
