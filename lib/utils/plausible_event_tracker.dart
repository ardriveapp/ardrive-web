import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

abstract class PlausibleEventTracker {
  static const String plausiblePageViewEventName = 'pageview';

  static final plausibleData = PlausibleApiData(
    api: Uri.parse('https://plausible.io/api/event'),
    domain: 'app.ardrive.io',
  );

  static Future<void> trackPageview({
    required PlausiblePageView event,
    Map<String, dynamic>? props,
  }) async {
    PlausibleEventData eventData = PlausibleEventData(
      name: plausiblePageViewEventName,
      url: Uri.parse(_eventUrl(event)),
    );

    eventData.props = {...(await _defaultEventProps()), ...?props};

    await _sendEvent(
      data: plausibleData,
      eventData: eventData,
    );
  }

  static Future<void> trackEvent({
    required PlausibleEvent event,
    Uri? url,
    Map<String, dynamic>? props,
  }) async {
    PlausibleEventData eventData = PlausibleEventData(
      name: event.name,
      url: url ?? Uri.base,
    );

    eventData.props = {...(await _defaultEventProps()), ...?props};

    await _sendEvent(
      data: plausibleData,
      eventData: eventData,
    );
  }

  static Future<Map<String, dynamic>> _defaultEventProps() async {
    Map<String, String> props = {
      'Platform': AppPlatform.getPlatform().name,
      'App Version': (await PackageInfo.fromPlatform()).version,
    };

    final androidVersion = await AppPlatform.androidVersion();

    if (androidVersion != null) {
      props['Android Version'] = androidVersion;
    }

    final iosVersion = await AppPlatform.iosVersion();

    if (iosVersion != null) {
      props['iOS Version'] = iosVersion;
    }

    final browserVersion = await AppPlatform.browserVersion();
    if (browserVersion != null) {
      props['Browser'] = browserVersion;
    }

    return props;
  }

  static Future<void> _sendEvent({
    required PlausibleApiData data,
    required PlausibleEventData eventData,
  }) async {
    Map<String, dynamic> body = {
      'name': eventData.name,
      'url': eventData.url.toString(),
      'domain': data.domain,
    };

    if (eventData.referrer != null) {
      body['referrer'] = eventData.referrer;
    }

    body['props'] = {...(await _defaultEventProps()), ...?eventData.props};

    try {
      await http.post(data.api, body: jsonEncode(body));

      logger.d('Sent plausible event: ${eventData.name}');
    } catch (e, s) {
      logger.e('Plausible response error: $e $s');
    }
  }

  static String _eventUrl(PlausiblePageView event) {
    return 'https://${plausibleData.domain}/${event.name}';
  }
}

class PlausibleApiData {
  final Uri api;
  final String domain;

  PlausibleApiData({
    required this.api,
    required this.domain,
  });
}

class PlausibleEventData {
  final String name;
  final Uri url;
  String? referrer;
  Map<String, dynamic>? props;

  PlausibleEventData({
    required this.name,
    required this.url,
    this.referrer,
    this.props,
  });
}

enum PlausiblePageView {
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

enum PlausibleEvent {
  uploadFile,
  uploadFolder,
  uploadReview,
}

extension PlausibleEventNames on PlausibleEvent {
  String get name {
    switch (this) {
      case PlausibleEvent.uploadFile:
        return 'Upload File';
      case PlausibleEvent.uploadFolder:
        return 'Upload Folder';
      case PlausibleEvent.uploadReview:
        return 'Upload Review';
      default:
        return 'Unknown';
    }
  }
}
