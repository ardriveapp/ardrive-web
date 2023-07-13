import 'package:ardrive/cookie_policy_consent/cookie_policy_consent.dart';
<<<<<<< Updated upstream
import 'package:ardrive/utils/logger/logger.dart';
=======
import 'package:bloc_concurrency/bloc_concurrency.dart';
>>>>>>> Stashed changes
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'cookie_policy_consent_event.dart';
part 'cookie_policy_consent_state.dart';

class CookiePolicyConsentBloc
    extends Bloc<CookiePolicyConsentEvent, CookiePolicyConsentState> {
  final ArDriveCookiePolicyConsent cookiePolicyConsent;

  CookiePolicyConsentBloc(
    this.cookiePolicyConsent,
  ) : super(CookiePolicyConsentInitial()) {
    on<CookiePolicyConsentEvent>(
      (event, emit) async {
        if (event is VerifyCookiePolicyConsent) {
          emit(VerifyingCookieConsent());

          final hasAcceptedCookiePolicyConsent =
              await cookiePolicyConsent.hasAcceptedCookiePolicy();

<<<<<<< Updated upstream
        if (hasAcceptedCookiePolicyConsent) {
          logger.i('User has accepted cookie policy consent');
          await Future.delayed(const Duration(milliseconds: 100));
          emit(CookiePolicyConsentAccepted());
        } else {
          logger.i('User has not accepted cookie policy consent');
          emit(CookiePolicyConsentRejected());
=======
          if (hasAcceptedCookiePolicyConsent) {
            emit(CookiePolicyConsentAccepted());
          } else {
            emit(CookiePolicyConsentRejected());
          }
        } else if (event is AcceptCookiePolicyConsent) {
          cookiePolicyConsent.acceptCookiePolicy();
          emit(CookiePolicyConsentAccepted());
>>>>>>> Stashed changes
        }
      },
      transformer: debounceSequential(const Duration(milliseconds: 100)),
    );
  }
}

/// The `VerifyingCookieConsent` and `CookiePolicyConsentRejected` states are debounced
/// to prevent this issue: https://github.com/felangel/bloc/issues/1392
///
EventTransformer<E> debounceSequential<E>(Duration duration) {
  return (events, mapper) {
    return sequential<E>().call(events.debounceTime(duration), mapper);
  };
}
