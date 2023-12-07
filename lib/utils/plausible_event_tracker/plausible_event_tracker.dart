import 'dart:convert';

import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_api_data.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_events.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_data.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_page_view_events.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

export 'package:ardrive/utils/plausible_event_tracker/plausible_custom_events.dart';
export 'package:ardrive/utils/plausible_event_tracker/plausible_page_view_events.dart';

abstract class PlausibleEventTracker {
  static const String _plausiblePageViewEventName = 'pageview';

  static final PlausibleApiData _plausibleData = PlausibleApiData(
    api: Uri.parse('https://plausible.io/api/event'),
    domain: 'app.ardrive.io',
  );

  static Future<void> trackPageview({
    required PlausiblePageView page,
    Map<String, dynamic>? props,
  }) async {
    PlausibleEventData eventData = PlausibleEventData(
      name: _plausiblePageViewEventName,
      url: Uri.parse(_getPageViewUrl(page)),
    );

    eventData.props = props;

    await _track(
      data: _plausibleData,
      eventData: eventData,
    );
  }

  static Future<void> _trackCustomEvent({
    required PlausiblePageView page,
    required PlausibleCustomEvent event,
    Map<String, dynamic>? props,
  }) async {
    PlausibleEventData eventData = PlausibleEventData(
      name: event.name,
      url: Uri.parse(_getPageViewUrl(page)),
    );

    eventData.props = props;

    await _track(
      data: _plausibleData,
      eventData: eventData,
    );
  }

  static Future<void> trackAppLoaded() async {
    final props = await _getAppLoadedEventProps();
    await _trackCustomEvent(
      page: PlausiblePageView.welcomePage,
      event: PlausibleCustomEvent.appLoaded,
      props: props.toJson(),
    );
  }

  static Future<void> trackNewButton({
    required NewButtonLocation location,
  }) async {
    final props = NewButtonProperties(
      location: location,
    );
    await _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.newButton,
      props: props.toJson(),
    );
  }

  static Future<void> tradckUploadReview({
    required DrivePrivacy drivePrivacy,
    required UploadType uploadType,
    required bool dragNDrop,
    required bool hasFolders,
    required bool hasSingleFile,
    required bool hasMultipleFiles,
  }) {
    final props = UploadReviewProperties(
      drivePrivacy: drivePrivacy,
      uploadType: uploadType,
      dragNDrop: dragNDrop,
      hasFolders: hasFolders,
      hasSingleFile: hasSingleFile,
      hasMultipleFiles: hasMultipleFiles,
    );

    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.uploadReview,
      props: props.toJson(),
    );
  }

  static Future<void> trackUploadConfirm() {
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.uploadConfirm,
    );
  }

  static Future<void> trackUploadSuccess() {
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.uploadSuccess,
    );
  }

  static Future<void> trackUploadFailure() {
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.uploadFailure,
    );
  }

  static Future<void> trackLogin({
    required LoginType type,
  }) {
    final props = LoginProperties(type: type);
    return _trackCustomEvent(
      page: PlausiblePageView.welcomeBackPage,
      event: PlausibleCustomEvent.login,
      props: props.toJson(),
    );
  }

  static Future<void> trackResync({
    required ResyncType type,
  }) {
    final props = ResyncProperties(type: type);
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.resync,
      props: props.toJson(),
    );
  }

  static Future<void> trackDriveCreation({
    required DrivePrivacy drivePrivacy,
  }) {
    final props = DriveCreationProperties(
      drivePrivacy: drivePrivacy,
    );
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.driveCreation,
      props: props.toJson(),
    );
  }

  static Future<void> trackFolderCreation({
    required DrivePrivacy drivePrivacy,
  }) {
    final props = FolderCreationProperties(
      drivePrivacy: drivePrivacy,
    );
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.folderCreation,
      props: props.toJson(),
    );
  }

  static Future<AppLoadedProperties> _getAppLoadedEventProps() async {
    final String platform = AppPlatform.getPlatform().name;
    final String platformVersion = await AppPlatform.androidVersion() ??
        await AppPlatform.iosVersion() ??
        await AppPlatform.browserVersion() ??
        'Unknown';
    final String appVersion = (await PackageInfo.fromPlatform()).version;

    final props = AppLoadedProperties(
      appVersion: appVersion,
      platform: platform,
      platformVersion: platformVersion,
    );

    return props;
  }

  static Future<void> _track({
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

    body['props'] = eventData.props;

    try {
      await http.post(data.api, body: jsonEncode(body));

      if (eventData.name == _plausiblePageViewEventName) {
        logger.d('Sent plausible pageview: ${eventData.url}');
      } else {
        logger.d(
          'Sent custom plausible event: ${eventData.name} (${eventData.url})'
          ' - props: ${body['props']}',
        );
      }
    } catch (e, s) {
      logger.e('Plausible response error: $e $s');
    }
  }

  static String _getPageViewUrl(PlausiblePageView event) {
    return 'https://${_plausibleData.domain}/${event.name}';
  }
}
