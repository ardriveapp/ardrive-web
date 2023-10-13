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

  static String _eventBody(PlausibleEvent event) {
    return jsonEncode({
      'name': event.name,
      'url': _eventUrl(event),
      'domain': _appDomain,
    });
  }

  static String _eventUrl(PlausibleEvent event) {
    return 'https://$_appDomain/${event.name}';
  }
}

enum PlausibleEvent {
  fileExplorerLoggedInUser, // implemented
  fileExplorerNewUserEmpty, // implemented
  fileExplorerNonLoggedInUser, // implemented
  tutorialsPage1, // implemented
  tutorialsPage2, // implemented
  tutorialsPage3, // implemented
  tutorialSkipped, // implemented
  createAndConfirmPasswordPage, // implemented
  createdAndConfirmedPassword, // implemented
  gettingStartedPage, // implemented
  returningUserPage,
  enterSeedPhrasePage, // implemented
  logout,
  onboardingPage, // implemented
  shareFilePage,
  turboPaymentDetails,
  turboPurchaseReview,
  turboTopUpModal,
  verifySeedPhrasePage,
  viewSeedPhrasePage,
  walletCreate, // is it different from walletGenerationPage
  walletDownloadPage, // implemented
  walletDownloaded, // implemented
  walletGenerationPage, // implemented
  welcomePage, // implemented
  welcomeBackPage, // implemented

  unknown,
}
