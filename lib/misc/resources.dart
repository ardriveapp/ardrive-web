class Resources {
  static const images = Images();
  static const arHelpLink =
      'https://ar-io.zendesk.com/hc/en-us/articles/5258520347419-Fund-Your-Wallet';
  static const manifestLearnMoreLink =
      'https://ar-io.zendesk.com/hc/en-us/articles/5300353421467-Arweave-Manifests';
  static const surveyFeedbackFormUrl = 'https://ar-io.typeform.com/UserSurvey';

  static const helpLink = 'https://ar-io.zendesk.com/hc/en-us';
  static const agreementLink = 'https://ardrive.io/tos-and-privacy/';
  static const getWalletLink = 'https://www.arconnect.io/';
}

class Images {
  const Images();

  final brand = const Brand();
  final profile = const Profile();
  final Login login = const Login();
}

class Brand {
  const Brand();
  final logoHorizontalNoSubtitleDark =
      'assets/images/brand/ArDrive-Logo-Wordmark-Light.png';
  final logoHorizontalNoSubtitleLight =
      'assets/images/brand/ArDrive-Logo-Wordmark-Dark.png';
  final logo05 = 'assets/images/brand/0.5x.png';
  final logo1 = 'assets/images/brand/1x.png';
  final logo2 = 'assets/images/brand/2x.png';
  final logo3 = 'assets/images/brand/3x.png';
  final logo4 = 'assets/images/brand/4x.png';

  final whiteLogo1 = 'assets/images/brand/white_logo_1x.png';
  final whiteLogo2 = 'assets/images/brand/white_logo_2x.png';
  final whiteLogo3 = 'assets/images/brand/white_logo_3x.png';
  final whiteLogo4 = 'assets/images/brand/white_logo_4x.png';
  final whiteLogo025 = 'assets/images/brand/white_logo_0.25x.png';
  final whiteLogo05 = 'assets/images/brand/white_logo_0.5x.png';

  final blackLogo1 = 'assets/images/brand/black_logo_1x.png';
  final blackLogo2 = 'assets/images/brand/black_logo_2x.png';
  final blackLogo025 = 'assets/images/brand/black_logo_0.25x.png';
  final blackLogo05 = 'assets/images/brand/black_logo_0.5x.png';
}

class Profile {
  const Profile();

  final profileAdd = 'assets/images/profile/profile_add.png';
  final profileOnboarding = 'assets/images/profile/profile_onboarding.png';
  final profileUnlock = 'assets/images/profile/profile_unlock.png';
  final profileWelcome = 'assets/images/profile/profile_welcome.png';

  final permahillsBg = 'assets/images/profile/profile_permahills_bg.svg';

  final newUserPermanent =
      'assets/images/profile/profile_new_user_permanent.png';
  final newUserPayment = 'assets/images/profile/profile_new_user_payment.png';
  final newUserUpload = 'assets/images/profile/profile_new_user_upload.png';
  final newUserPrivate = 'assets/images/profile/profile_new_user_private.png';
  final newUserDelete = 'assets/images/profile/profile_new_user_delete.png';
}

class Login {
  const Login();

  final String gridImage = 'assets/images/login/grid_images.png';
  final String ardriveLogoOnboarding = 'assets/images/brand/2x.png';
  final String arconnectLogo = 'assets/images/login/arconnect_logo.png';
}
