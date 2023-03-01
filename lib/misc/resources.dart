class Resources {
  static const images = Images();
  static const arHelpLink =
      'https://ar-io.zendesk.com/hc/en-us/articles/5258520347419-Fund-Your-Wallet';
  static const manifestLearnMoreLink =
      'https://ar-io.zendesk.com/hc/en-us/articles/5300353421467-Arweave-Manifests';
  static const surveyFeedbackFormUrl = 'https://ar-io.typeform.com/UserSurvey';
  static const infernoRulesLinkEn = 'https://ardrive.io/inferno/';
  static const infernoRulesLinkZh = 'https://cn.ardrive.io/inferno/';

  static const helpLink = 'https://ar-io.zendesk.com/hc/en-us';
  static const agreementLink = 'https://ardrive.io/tos-and-privacy/';
  static const getWalletLink = 'https://tokens.arweave.org/';
}

class Images {
  const Images();

  final brand = const Brand();
  final profile = const Profile();
  final inferno = const Inferno();
  final Login login = const Login();
  final fileTypes = const FileTypes();
}

class FileTypes {
  const FileTypes();

  final code = 'assets/images/file_types/code.png';
  final doc = 'assets/images/file_types/doc.png';
  final folder = 'assets/images/file_types/folder.png';
  final image = 'assets/images/file_types/image.png';
  final music = 'assets/images/file_types/music.png';
  final video = 'assets/images/file_types/video.png';
}

class Brand {
  const Brand();
  final logoHorizontalNoSubtitleDark =
      'assets/images/brand/ArDrive-Logo-Wordmark-Light.png';
  final logoHorizontalNoSubtitleLight =
      'assets/images/brand/ArDrive-Logo-Wordmark-Dark.png';
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

class Inferno {
  const Inferno();

  final fire = 'assets/images/inferno/fire_icon.png';
}

class Login {
  const Login();

  final String login1 = 'assets/images/login/login_1.png';
  final String login2 = 'assets/images/login/login_2.png';
  final String login3 = 'assets/images/login/login_3.png';
  final String login4 = 'assets/images/login/login_4.png';
  final String arconnectLogo = 'assets/images/login/arconnect_logo.png';
  final OnBoarding onboarding = const OnBoarding();
}

class OnBoarding {
  const OnBoarding();

  final String onboarding1 = 'assets/images/login/onboarding/onboarding_1.png';
  final String onboarding2 = 'assets/images/login/onboarding/onboarding_2.png';
  final String onboarding3 = 'assets/images/login/onboarding/onboarding_3.png';
  final String onboarding4 = 'assets/images/login/onboarding/onboarding_4.png';
  final String onboarding5 = 'assets/images/login/onboarding/onboarding_5.png';
  final String onboarding6 = 'assets/images/login/onboarding/onboarding_6.png';
}
