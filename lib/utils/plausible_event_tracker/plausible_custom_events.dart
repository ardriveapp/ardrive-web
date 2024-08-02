enum PlausibleCustomEvent {
  appLoaded,
  attachDrive,
  driveCreation,
  folderCreation,
  login,
  newButton,
  pinCreation,
  resync,
  snapshotCreation,
  uploadReview,
  uploadConfirm,
  uploadSuccess,
  uploadFailure,

  /// <<<-----------------New Onboarding Events------------------>>>
  ///
  /// Welcome to ArDrive Page Events
  clickSignUp,
  clickLogin,

  /// SignUp Page Events
  clickContinueWithArconnectButton,
  clickContinueWithMetamaskButton,
  clickCreateWallet,
  clickAlreadyHaveAWallet,
  clickConfirmPassword,
  clickTutorialNextButton,
  clickTutorialBackButton,
  clickKeyfileInfo,
  clickSeedPhraseInfo,
  clickSecurityInfo,
  clickHideSeedPhraseIcon,
  clickRevealSeedPhraseIcon,
  clickCopySeedPhraseIcon,
  clickCopySeedPhraseButton,
  clickDownloadKeyfileButton,
  clickBackedUpSeedPhraseCheckBox,
  clickGoToAppButton,
  clickTutorialGoToAppLink,
  clickTutorialGetYourWallet,

  /// Login
  clickImANewUserLinkButton,
  clickUseKeyfileButton,
  clickContinueWithSeedphraseButton,
  clickLoginHidePassword,
  clickLoginRevealPassword,
  clickDismissLoginModalIcon,
  clickContinueLoginButton,
  clickImportWalletButton,

  /// Returning User
  clickContinueReturnUserButton,
  clickForgetWalletTextButton,
  pressEnterContinueReturnUser,

  /// Theme Switcher
  clickThemeSwitcherLight,
  clickThemeSwitcherDark,

  /// Terms of Services
  clickTermsOfServices,

  /// Create Drive on Empty State
  clickCreatePrivateDriveButtonEmptyState,
  clickCreatePublicDriveButtonEmptyState,

  /// Drive Empty State
  clickUploadFileEmptyState,
  clickCreateFolderEmptyState,
  clickUploadFolderEmptyState,
  clickCreatePinEmptyState,
}

extension PlausibleCustomEventNames on PlausibleCustomEvent {
  String get name {
    switch (this) {
      case PlausibleCustomEvent.appLoaded:
        return 'App Loaded';
      case PlausibleCustomEvent.attachDrive:
        return 'Attach Drive';
      case PlausibleCustomEvent.driveCreation:
        return 'Drive Creation';
      case PlausibleCustomEvent.folderCreation:
        return 'Folder Creation';
      case PlausibleCustomEvent.login:
        return 'Login';
      case PlausibleCustomEvent.newButton:
        return 'New Button';
      case PlausibleCustomEvent.pinCreation:
        return 'Pin Creation';
      case PlausibleCustomEvent.resync:
        return 'Resync';
      case PlausibleCustomEvent.snapshotCreation:
        return 'Snapshot Creation';
      case PlausibleCustomEvent.uploadReview:
        return 'Upload Review';
      case PlausibleCustomEvent.uploadConfirm:
        return 'Upload Confirm';
      case PlausibleCustomEvent.uploadSuccess:
        return 'Upload Success';
      case PlausibleCustomEvent.uploadFailure:
        return 'Upload Failure';

      /// Welcome to ArDrive Page Events
      case PlausibleCustomEvent.clickSignUp:
        return 'clickSignUp';
      case PlausibleCustomEvent.clickLogin:
        return 'clickLogin';

      /// SignUp Page Events
      case PlausibleCustomEvent.clickContinueWithArconnectButton:
        return 'clickContinueWithArconnect';
      case PlausibleCustomEvent.clickContinueWithMetamaskButton:
        return 'clickContinueWithMetamask';
      case PlausibleCustomEvent.clickCreateWallet:
        return 'clickCreateWallet';
      case PlausibleCustomEvent.clickAlreadyHaveAWallet:
        return 'clickAlreadyHaveAWallet';
      case PlausibleCustomEvent.clickConfirmPassword:
        return 'clickConfirmPassword';
      case PlausibleCustomEvent.clickTutorialNextButton:
        return 'clickTutorialNext';
      case PlausibleCustomEvent.clickTutorialBackButton:
        return 'clickTutorialBack';
      case PlausibleCustomEvent.clickKeyfileInfo:
        return 'clickKeyfileInfo';
      case PlausibleCustomEvent.clickSeedPhraseInfo:
        return 'clickSeedPhraseInfo';
      case PlausibleCustomEvent.clickSecurityInfo:
        return 'clickSecurityInfo';
      case PlausibleCustomEvent.clickHideSeedPhraseIcon:
        return 'clickHideSeedPhraseIcon';
      case PlausibleCustomEvent.clickRevealSeedPhraseIcon:
        return 'clickRevealSeedPhraseIcon';
      case PlausibleCustomEvent.clickCopySeedPhraseIcon:
        return 'clickCopySeedPhraseIcon';
      case PlausibleCustomEvent.clickCopySeedPhraseButton:
        return 'clickCopySeedPhraseButton';
      case PlausibleCustomEvent.clickDownloadKeyfileButton:
        return 'clickDownloadKeyfileButton';
      case PlausibleCustomEvent.clickBackedUpSeedPhraseCheckBox:
        return 'clickBackedUpSeedPhraseCheckBox';
      case PlausibleCustomEvent.clickGoToAppButton:
        return 'clickGoToAppButton';
      case PlausibleCustomEvent.clickTutorialGoToAppLink:
        return 'clickTutorialGoToAppLink';
      case PlausibleCustomEvent.clickTutorialGetYourWallet:
        return 'clickTutorialGetYourWallet';

      /// Returning User
      case PlausibleCustomEvent.clickContinueReturnUserButton:
        return 'clickContinueReturnUserButton';
      case PlausibleCustomEvent.clickForgetWalletTextButton:
        return 'clickForgetWalletTextButton';
      case PlausibleCustomEvent.pressEnterContinueReturnUser:
        return 'pressEnterContinueReturnUser';

      /// Login
      case PlausibleCustomEvent.clickImANewUserLinkButton:
        return 'clickImANewUserLinkButton';
      case PlausibleCustomEvent.clickImportWalletButton:
        return 'clickImportWalletButton';
      case PlausibleCustomEvent.clickUseKeyfileButton:
        return 'clickUseKeyfileButton';
      case PlausibleCustomEvent.clickContinueWithSeedphraseButton:
        return 'clickContinueWithSeedphraseButton';
      case PlausibleCustomEvent.clickLoginHidePassword:
        return 'clickLoginHidePassword';
      case PlausibleCustomEvent.clickLoginRevealPassword:
        return 'clickLoginRevealPassword';
      case PlausibleCustomEvent.clickDismissLoginModalIcon:
        return 'clickDismissLoginModalIcon';
      case PlausibleCustomEvent.clickContinueLoginButton:
        return 'clickContinueLoginButton';

      /// Theme Switcher
      case PlausibleCustomEvent.clickThemeSwitcherLight:
        return 'clickThemeSwitcherLight';
      case PlausibleCustomEvent.clickThemeSwitcherDark:
        return 'clickThemeSwitcherDark';

      /// Terms of Services
      case PlausibleCustomEvent.clickTermsOfServices:
        return 'clickTermsOfServices';

      /// Create Drive
      case PlausibleCustomEvent.clickCreatePrivateDriveButtonEmptyState:
        return 'clickCreatePrivateDriveButtonEmptyState';
      case PlausibleCustomEvent.clickCreatePublicDriveButtonEmptyState:
        return 'clickCreatePublicDriveButtonEmptyState';

      /// Drive Empty State
      case PlausibleCustomEvent.clickUploadFileEmptyState:
        return 'clickUploadFileEmptyState';
      case PlausibleCustomEvent.clickCreateFolderEmptyState:
        return 'clickCreateFolderEmptyState';
      case PlausibleCustomEvent.clickUploadFolderEmptyState:
        return 'clickUploadFolderEmptyState';
      case PlausibleCustomEvent.clickCreatePinEmptyState:
        return 'clickCreatePinEmptyState';
    }
  }
}
