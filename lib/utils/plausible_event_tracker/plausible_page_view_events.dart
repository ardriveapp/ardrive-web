enum PlausiblePageView {
  fileExplorerPage,
  fileExplorerLoggedInUser, // TODO: remove - why: the above is the same
  fileExplorerNewUserEmpty, // TODO: remove
  fileExplorerNonLoggedInUser, // TODO: remove
  tutorialsPage1, // TODO: remove - why: it's the same onboarding page, these should be events
  tutorialsPage2, // TODO: remove
  tutorialsPage3, // TODO: remove
  tutorialSkipped, // TODO: remove
  createdAndConfirmedPassword, // TODO: remove - why: it should be an event
  gettingStartedPage,
  enterSeedPhrasePage,
  logout, // TODO: remove - why: it should be an event
  onboardingPage,
  sharedFilePage,
  turboPaymentDetails, // TODO: remove - why: this is a modal, these should be events
  turboPurchaseReview, // TODO: remove
  turboTopUpModal, // TODO: remove
  turboTopUpCancel, // TODO: remove
  turboTopUpSuccess, // TODO: remove
  verifySeedPhrasePage,
  writeDownSeedPhrasePage,
  walletDownloadPage,
  walletDownloaded, // TODO: remove - why: it should be an event
  walletGenerationPage,
  welcomePage,
  welcomeBackPage,
  unknown,

  /// New Onboarding Events
  signUpPage,
  createAndConfirmPasswordPage,
  generateWalletLoader,
  walletCreatedPage,
  loginPage,
  importWalletPage,
  enterPasswordPage,
  returnUserPage,

  /// Search
  searchPage,

  /// Empty State
  folderEmptyPage,
  existingUserDriveEmptyPage,
  newUserDriveEmptyPage,
}
