import 'package:ardrive/cookie_policy_consent/blocs/cookie_policy_consent_bloc.dart';
import 'package:ardrive/cookie_policy_consent/cookie_policy_consent.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows the cookie policy consent modal. If the user accepts the cookie policy
/// consent, the turbo modal will be shown.
///
Future<void> showCookiePolicyConsentModal(
    BuildContext context, Function(BuildContext) onAccept) {
  final bloc = CookiePolicyConsentBloc(
    ArDriveCookiePolicyConsent(),
  )..add(VerifyCookiePolicyConsent());

  return showAnimatedDialog(
    context,
    barrierDismissible: false,
    content: BlocProvider<CookiePolicyConsentBloc>(
      create: (_) => bloc,
      child: CookieConsentModal(
        onAccept: onAccept,
      ),
    ),
  );
}

class CookieConsentModal extends StatelessWidget {
  const CookieConsentModal({
    super.key,
    required this.onAccept,
  });

  final Function(BuildContext) onAccept;

  @override
  Widget build(BuildContext context) {
    return BlocListener<CookiePolicyConsentBloc, CookiePolicyConsentState>(
      listener: (context, state) {
        if (state is CookiePolicyConsentAccepted) {
          Navigator.pop(context);
          onAccept(context);
        }
      },
      child: BlocBuilder<CookiePolicyConsentBloc, CookiePolicyConsentState>(
        builder: (context, state) {
          if (state is CookiePolicyConsentRejected) {
            return ArDriveStandardModal(
              hasCloseButton: true,
              title: appLocalizationsOf(context).cookieConsent,
              content: Text(
                appLocalizationsOf(context).cookieConsentBody,
                style: ArDriveTypography.body.buttonLargeBold(),
              ),
              actions: [
                ModalAction(
                  action: () {
                    context
                        .read<CookiePolicyConsentBloc>()
                        .add(AcceptCookiePolicyConsent());
                  },
                  title: appLocalizationsOf(context).accept,
                ),
              ],
            );
          }

          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}
