import 'dart:convert';

import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/utils/logger.dart';
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

  static Future<void> trackUploadReview({
    required DrivePrivacy drivePrivacy,
    required bool dragNDrop,
  }) {
    final props = UploadReviewProperties(
      drivePrivacy: drivePrivacy,
      dragNDrop: dragNDrop,
    );

    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.uploadReview,
      props: props.toJson(),
    );
  }

  static Future<void> trackUploadConfirm({
    required UploadType uploadType,
    required UploadContains uploadContains,
  }) {
    final props = UploadConfirmProperties(
      uploadType: uploadType,
      uploadContains: uploadContains,
    );
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.uploadConfirm,
      props: props.toJson(),
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

  static Future<void> trackPinCreation({
    required DrivePrivacy drivePrivacy,
  }) {
    final props = PinCreationProperties(
      drivePrivacy: drivePrivacy,
    );
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.pinCreation,
      props: props.toJson(),
    );
  }

  static Future<void> trackSnapshotCreation({
    required DrivePrivacy drivePrivacy,
  }) {
    final props = SnapshotCreationProperties(
      drivePrivacy: drivePrivacy,
    );
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.snapshotCreation,
      props: props.toJson(),
    );
  }

  static Future<void> trackAttachDrive({
    required DrivePrivacy drivePrivacy,
  }) {
    final props = AttachDriveProperties(
      drivePrivacy: drivePrivacy,
    );
    return _trackCustomEvent(
      page: PlausiblePageView.fileExplorerPage,
      event: PlausibleCustomEvent.attachDrive,
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

  /// New Onboarding Events
  ///
  /// Welcome Page
  static Future<void> trackClickSignUp() {
    return _trackCustomEvent(
      page: PlausiblePageView.welcomePage,
      event: PlausibleCustomEvent.clickSignUp,
    );
  }

  static Future<void> trackClickLogin() {
    return _trackCustomEvent(
      page: PlausiblePageView.welcomePage,
      event: PlausibleCustomEvent.clickLogin,
    );
  }

  /// Return User Page
  static Future<void> trackClickContinueReturnUserButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.returnUserPage,
      event: PlausibleCustomEvent.clickContinueReturnUserButton,
    );
  }

  static Future<void> trackClickForgetWalletTextButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.returnUserPage,
      event: PlausibleCustomEvent.clickForgetWalletTextButton,
    );
  }

  // pressEnterContinueReturnUser
  static Future<void> trackPressEnterContinueReturnUser() {
    return _trackCustomEvent(
      page: PlausiblePageView.returnUserPage,
      event: PlausibleCustomEvent.pressEnterContinueReturnUser,
    );
  }

  /// Login
  static Future<void> trackClickContinueLoginButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.importWalletPage,
      event: PlausibleCustomEvent.clickContinueLoginButton,
    );
  }

  static Future<void> trackClickContinueWithArconnectButton(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickContinueWithArconnectButton,
    );
  }

  static Future<void> trackClickContinueWithMetamaskButton(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickContinueWithMetamaskButton,
    );
  }

  static Future<void> trackClickImANewUserLinkButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.loginPage,
      event: PlausibleCustomEvent.clickImANewUserLinkButton,
    );
  }

  static Future<void> trackClickImportWalletButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.loginPage,
      event: PlausibleCustomEvent.clickImportWalletButton,
    );
  }

  static Future<void> trackClickUseKeyfileButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.importWalletPage,
      event: PlausibleCustomEvent.clickUseKeyfileButton,
    );
  }

  static Future<void> trackClickContinueWithSeedphraseButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.importWalletPage,
      event: PlausibleCustomEvent.clickContinueWithSeedphraseButton,
    );
  }

  static Future<void> trackClickDismissLoginModalIcon(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickDismissLoginModalIcon,
    );
  }

  // Sign Up
  static Future<void> trackClickAlreadyHaveAWallet() {
    return _trackCustomEvent(
      page: PlausiblePageView.signUpPage,
      event: PlausibleCustomEvent.clickAlreadyHaveAWallet,
    );
  }

  static Future<void> trackClickCreateWallet() {
    return _trackCustomEvent(
      page: PlausiblePageView.signUpPage,
      event: PlausibleCustomEvent.clickCreateWallet,
    );
  }

  static Future<void> trackClickTermsOfServices(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickTermsOfServices,
    );
  }

  static Future<void> trackClickConfirmPassword() {
    return _trackCustomEvent(
      page: PlausiblePageView.createAndConfirmPasswordPage,
      event: PlausibleCustomEvent.clickConfirmPassword,
    );
  }

  static Future<void> trackClickTutorialNextButton(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickTutorialNextButton,
    );
  }

  static Future<void> trackClickTutorialBackButton(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickTutorialBackButton,
    );
  }

  static Future<void> trackClickTutorialGetYourWallet() {
    return _trackCustomEvent(
      page: PlausiblePageView.tutorialsPage3,
      event: PlausibleCustomEvent.clickTutorialGetYourWallet,
    );
  }

  static Future<void> trackClickTutorialGoToAppLink() {
    return _trackCustomEvent(
      page: PlausiblePageView.tutorialsPage3,
      event: PlausibleCustomEvent.clickTutorialGoToAppLink,
    );
  }

  static Future<void> trackClickGoToAppButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.walletCreatedPage,
      event: PlausibleCustomEvent.clickGoToAppButton,
    );
  }

  // Theme Switcher
  static Future<void> trackClickThemeSwitcherLight(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickThemeSwitcherLight,
    );
  }

  static Future<void> trackClickThemeSwitcherDark(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickThemeSwitcherDark,
    );
  }

  // clickKeyfileInfo
  static Future<void> trackClickKeyfileInfo() {
    return _trackCustomEvent(
      page: PlausiblePageView.walletCreatedPage,
      event: PlausibleCustomEvent.clickKeyfileInfo,
    );
  }

  // clickCopySeedPhraseButton
  static Future<void> trackClickCopySeedPhraseButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.walletCreatedPage,
      event: PlausibleCustomEvent.clickCopySeedPhraseButton,
    );
  }

  // clickDownloadKeyfileButton
  static Future<void> trackClickDownloadKeyfileButton() {
    return _trackCustomEvent(
      page: PlausiblePageView.walletCreatedPage,
      event: PlausibleCustomEvent.clickDownloadKeyfileButton,
    );
  }

  // clickCopySeedPhraseIcon
  static Future<void> trackClickCopySeedPhraseIcon() {
    return _trackCustomEvent(
      page: PlausiblePageView.walletCreatedPage,
      event: PlausibleCustomEvent.clickCopySeedPhraseIcon,
    );
  }

  // clickBackedUpSeedPhraseCheckBox
  static Future<void> trackClickBackedUpSeedPhraseCheckBox() {
    return _trackCustomEvent(
      page: PlausiblePageView.walletCreatedPage,
      event: PlausibleCustomEvent.clickBackedUpSeedPhraseCheckBox,
    );
  }

  // clickCreatePublicDriveButton
  static Future<void> trackClickCreatePublicDriveButton(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickCreatePublicDriveButtonEmptyState,
    );
  }

  // clickCreatePrivateDriveButton
  static Future<void> trackClickCreatePrivateDriveButton(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickCreatePrivateDriveButtonEmptyState,
    );
  }

  // clickUploadFileEmptyState,
  static Future<void> trackClickUploadFileEmptyState(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickUploadFileEmptyState,
    );
  }

  // clickCreateFolderEmptyState
  static Future<void> trackClickCreateFolderEmptyState(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickCreateFolderEmptyState,
    );
  }

  // clickUploadFolderEmptyState
  static Future<void> trackClickUploadFolderEmptyState(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickUploadFolderEmptyState,
    );
  }

  // clickCreatePinEmptyState
  static Future<void> trackClickCreatePinEmptyState(
    PlausiblePageView page,
  ) {
    return _trackCustomEvent(
      page: page,
      event: PlausibleCustomEvent.clickCreatePinEmptyState,
    );
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
      logger.w('Plausible response error: $e $s');
    }
  }

  static String _getPageViewUrl(PlausiblePageView event) {
    return 'https://${_plausibleData.domain}/${event.name}';
  }
}
