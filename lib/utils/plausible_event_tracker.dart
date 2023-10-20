import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:http/http.dart' as http;

abstract class PlausibleEventTracker {
  static const String _plausibleUrlString = 'https://plausible.io/api/event';
  static const String _appDomain = 'app.ardrive.io';

  static Uri get _plausibleUrl => Uri.parse(_plausibleUrlString);

  static Future<void> trackCustomEvent({
    required ArDrivePage page,
    required ArDriveEvent event,
  }) async {
    // FIXME: un-comment this when custom events are set up in plausible
    /// for now we are just tracking them as page views
    //
    // return _track(pageName: page.name, customEventName: event.name);

    return _track(pageName: event.name);
  }

  static Future<void> trackPageView({required ArDrivePage page}) async {
    return _track(pageName: page.name);
  }

  static Future<void> _track({
    required String pageName,
    String? customEventName,
  }) async {
    final eventName = customEventName ?? ArDriveEvent.pageview.name;
    try {
      await http.post(_plausibleUrl,
          body: _eventBody(
            pageName,
            customEventName: eventName,
          ));

      logger.d('Sent plausible event: $eventName on page: $pageName');
    } catch (e, s) {
      logger.e('Plausible response error: $e $s');
    }
  }

  static String _eventBody(
    String pageName, {
    required String customEventName,
  }) {
    final eventName = customEventName;
    return jsonEncode({
      'name': eventName,
      'url': _pageUrl(pageName),
      'domain': _appDomain,
    });
  }

  static String _pageUrl(String pageName) {
    return 'https://$_appDomain/$pageName';
  }
}

enum ArDrivePage {
  createAndConfirmPassword,
  fileExplorer,
  gettingStarted,
  enterSeedPhrase,
  onboarding,
  profile,
  sharedFile,
  turboTopUpModal,
  verifySeedPhrase,
  writeDownSeedPhrase,
  walletDownload,
  walletGeneration,
  landing,
  welcomeBack,
}

enum ArDriveEvent {
  fileExplorerLoggedInUser,
  fileExplorerNewUserEmpty,
  fileExplorerNonLoggedInUser,
  tutorialsPage1,
  tutorialsPage2,
  tutorialsPage3,
  tutorialSkipped,
  createdAndConfirmedPassword,
  logout,
  turboTopUpCancel,
  turboTopUpSuccess,
  turboPaymentDetails,
  turboPurchaseReview,
  walletDownloaded,

  pageview,
}
