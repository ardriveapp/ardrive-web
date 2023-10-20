import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:http/http.dart' as http;

abstract class PlausibleEventTracker {
  static Future<void> trackCustomEvent({
    required ArDrivePage page,
    required ArDriveEvent event,
    PlausibleApi? plausibleApi,
  }) async {
    // FIXME: un-comment this when custom events are set up in plausible
    /// for now we are just tracking them as page views
    //
    // return _track(pageName: page.name, customEventName: event.name);

    return _track(
      pageName: event.name,
      plausibleApi: plausibleApi ?? PlausibleApi(),
    );
  }

  static Future<void> trackPageView({
    required ArDrivePage page,
    PlausibleApi? plausibleApi,
  }) async {
    return _track(
      pageName: page.name,
      plausibleApi: plausibleApi ?? PlausibleApi(),
    );
  }

  static Future<void> _track({
    required String pageName,
    String? customEventName,
    required PlausibleApi plausibleApi,
  }) async {
    return plausibleApi.track(
      pageName: pageName,
      customEventName: customEventName,
    );
  }
}

class PlausibleApi {
  final String _plausibleUrlString = 'https://plausible.io/api/event';
  final String _appDomain = 'app.ardrive.io';

  Uri get _plausibleUrl => Uri.parse(_plausibleUrlString);

  const PlausibleApi._();
  static const PlausibleApi _instance = PlausibleApi._();
  factory PlausibleApi() => _instance;

  Future<void> track({
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

  String _eventBody(
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

  String _pageUrl(String pageName) {
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
