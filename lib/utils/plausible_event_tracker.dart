import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:http/http.dart' as http;

abstract class PlausibleEventTracker {
  static const String _plausibleUrlString = 'https://plausible.io/api/event';
  static const String _appDomain = 'app.ardrive.io';

  static Uri get _plausibleUrl => Uri.parse(_plausibleUrlString);

  static Future<void> track({required PlausibleEvent event}) async {
    try {
      final response = await http.post(_plausibleUrl, body: _eventBody(event));

      logger.d('Plausible response: ${response.statusCode}');
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
  arDriveFileExplorerLoggedInUser,
  arDriveFileExplorerNewUserEmpty,
  arDriveFileExplorerNonLoggedInUser,
  arDriveTutorialsPage1,
  arDriveTutorialsPage2,
  arDriveTutorialsPage3,
  createAndConfirmPasswords,
  downloadKeyFile,
  gettingStartedPage,
  loginPage,
  returningUserPage,
  seedPhrasePage,
  shareFilePage,
  turboPaymentDetails,
  turboPurchaseReview,
  turboTopUpModal,
  verifySeedPhrasePage,
  viewSeedPhrasePage,
  walletCreate,
  walletDownloadPage,
  walletGenerationPage,
  welcomePage,
  welcomeBackPage,

  unknown,
}
