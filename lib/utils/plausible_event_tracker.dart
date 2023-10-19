import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:http/http.dart' as http;

abstract class PlausibleEventTracker {
  static const String _plausibleUrlString = 'https://plausible.io/api/event';
  static const String _appDomain = 'app.ardrive.io';

  static Uri get _plausibleUrl => Uri.parse(_plausibleUrlString);

  static Future<void> track({required PlausibleEvent event}) async {
    try {
      await http.post(_plausibleUrl, body: _eventBody(event));

      logger.d('Sent plausible event: ${event.name}');
    } catch (e, s) {
      logger.e('Plausible response error: $e $s');
    }
  }

  static String _eventBody(
    PlausibleEvent event, {
    String eventName = plausiblePageViewEventName,
  }) {
    return jsonEncode({
      'name': eventName,
      'url': _eventUrl(event),
      'domain': _appDomain,
    });
  }

  static String _eventUrl(PlausibleEvent event) {
    return 'https://$_appDomain/${event.name}';
  }
}

const String plausiblePageViewEventName = 'pageview';

enum PlausibleEvent {
  fileExplorerLoggedInUser,
  fileExplorerNewUserEmpty,
  fileExplorerNonLoggedInUser,
  tutorialsPage1,
  tutorialsPage2,
  tutorialsPage3,
  tutorialSkipped,
  createAndConfirmPasswordPage,
  createdAndConfirmedPassword,
  gettingStartedPage,
  enterSeedPhrasePage,
  logout,
  onboardingPage,
  sharedFilePage,
  turboPaymentDetails,
  turboPurchaseReview,
  turboTopUpModal,
  turboTopUpCancel,
  turboTopUpSuccess,
  verifySeedPhrasePage,
  writeDownSeedPhrasePage,
  walletDownloadPage,
  walletDownloaded,
  walletGenerationPage,
  welcomePage,
  welcomeBackPage,

  unknown,
}
