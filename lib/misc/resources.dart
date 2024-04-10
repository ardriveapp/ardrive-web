class Resources {
  static const images = Images();
  static const arHelpLink =
      'https://ardrive.zendesk.com/hc/en-us/articles/5258520347419-Fund-Your-Wallet';
  static const manifestLearnMoreLink =
      'https://ardrive.zendesk.com/hc/en-us/articles/5300353421467-Arweave-Manifests';
  static const surveyFeedbackFormUrl =
      'https://pds-inc.typeform.com/UserSurvey';

  static const helpLink = 'https://ardrive.zendesk.com/hc/en-us';
  static const ardrivePublicSiteLink = 'https://ardrive.io/';
  static const agreementLink = 'https://ardrive.io/tos-and-privacy/';
  static const getWalletLink = 'https://www.arconnect.io/';
  static const sendGiftLink = 'http://gift.ardrive.io/';
  static const licenseHelpLink =
      'https://help.ardrive.io/hc/en-us/articles/23162949343131-Licensing-Your-Data';

  static const howDoesKeyFileLoginWork =
      'https://help.ardrive.io/hc/en-us/articles/15412384724251-How-Do-Keyfile-and-Seed-Phrase-Login-Work-';
  static const howAreConversionsDetermined =
      'https://help.ardrive.io/hc/en-us/articles/17043397992731';
  static const cookiePolicy = 'https://stripe.com/legal/cookies-policy';
  static const emailSupport = 'support@ardrive.io';
  static const helpCenterLink =
      'https://help.ardrive.io/hc/en-us/articles/9350732157723-Contact-Us';
  static const discordLink = 'https://discord.gg/KkTqDe4GAF';

  static const ardriveAppLimits =
      'https://help.ardrive.io/hc/en-us/articles/5300389777179-ArDrive-App-';
  static const priceCalculatorLink = 'https://ardrive.io/pricing';
}

class Images {
  const Images();

  final brand = const Brand();
  final profile = const Profile();
  final Login login = const Login();
  final icons = const _Icons();
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
  final turboWhite = 'assets/images/brand/turbo-white.svg';
  final turboBlack = 'assets/images/brand/turbo-black.svg';
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

  final String gridImage = 'assets/images/login/grid_images.jpg';
  final String ardriveLogoOnboarding = 'assets/images/brand/2x.png';
  final String arconnectLogo = 'assets/images/login/arconnect_logo_flat.svg';
  final String lattice = 'assets/images/login/lattice.svg';
  final String latticeLight = 'assets/images/login/lattice_light.svg';
  final String latticeLarge = 'assets/images/login/lattice_large.svg';
  final String latticeLargeLight =
      'assets/images/login/lattice_large_light.svg';
  final String confetti = 'assets/images/login/confetti.png';
  final String confettiLeft = 'assets/images/login/confetti_left.png';
  final String confettiRight = 'assets/images/login/confetti_right.png';
  final String arrowRed = 'assets/images/login/arrow_red.svg';
  final String ardriveLoader = 'assets/images/login/ardrive_loader.gif';
  final String checkCircle = 'assets/images/login/check_circle.png';
  final String whatIsAKeyfile = 'assets/images/login/what_is_a_keyfile.png';
  final String aboutSecurity = 'assets/images/login/about_security.png';

  final String metamask = 'assets/images/login/metamask_logo_flat.svg';
  final String walletUpload = 'assets/images/login/wallet_upload.svg';

  final String particleSpace = 'assets/images/login/particle_space.png';
  final String dataStorage = 'assets/images/login/data_storage.svg';
  final String bento2 = 'assets/images/login/bento_box/Bento-2.svg';

  final BentoBox bentoBox = const BentoBox();
}

class BentoBox {
  final String profile1 = 'assets/images/login/bento_box/profile_1.png';
  final String profile2 = 'assets/images/login/bento_box/profile_2.png';
  final String profile3 = 'assets/images/login/bento_box/profile_3.png';
  final String profile4 = 'assets/images/login/bento_box/profile_4.png';
  final String profile5 = 'assets/images/login/bento_box/profile_5.png';
  final String profile6 = 'assets/images/login/bento_box/profile_6.png';
  final String noSubscription =
      'assets/images/login/bento_box/no_subscription.svg';
  final String decentralized =
      'assets/images/login/bento_box/decentralized.svg';
  final String permanentAccessibleData =
      'assets/images/login/bento_box/permanent_accesible_data.svg';
  final String priceCalculator =
      'assets/images/login/bento_box/price_calculator.svg';
  final String dots = 'assets/images/login/bento_box/dots.png';
  final String bg = 'assets/images/login/bento_box/Bg.png';

  const BentoBox();
}

class _Icons {
  const _Icons();

  final String alert = 'assets/images/icons/iconAlert.svg';
  final String copy = 'assets/images/icons/iconCopy.svg';
  final String download = 'assets/images/icons/iconDownload.svg';
  final String encryptedLock = 'assets/images/icons/iconEncryptedLock.svg';
  final String eyeOpen = 'assets/images/icons/iconEyeOpen.svg';
  final String eyeClosed = 'assets/images/icons/iconEyeClosed.svg';
}

const String discord = 'Discord';
