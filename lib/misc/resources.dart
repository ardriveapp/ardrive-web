class Resources {
  static const images = Images();
  static const surveyFeedbackFormUrl = 'https://pds-inc.typeform.com/ardrive';

  static const ardrivePublicSiteLink = 'https://ardrive.io/';
  static const agreementLink = 'https://ardrive.io/tos-and-privacy/';
  static const getWalletLink = 'https://www.wander.app/';
  static const sendGiftLink = 'https://turbo.ar.io/gift';
  static const licenseHelpLink =
      'https://help.ardrive.io/hc/en-us/articles/23162949343131-Licensing-Your-Data';
  static const manifestLearnMoreLink =
      'https://docs.ar.io/build/upload/manifests';

  static const howDoesKeyFileLoginWork =
      'https://help.ardrive.io/hc/en-us/articles/15412384724251-How-Do-Keyfile-and-Seed-Phrase-Login-Work-';
  static const howAreConversionsDetermined =
      'https://docs.ar.io/build/upload/turbo-credits';
  static const cookiePolicy = 'https://stripe.com/legal/cookies-policy';
  static const emailSupport = 'support@ardrive.io';
  static const helpCenterLink = 'https://ardrive.io/contact';
  static const discordLink = 'https://discord.gg/KkTqDe4GAF';

  static const ardriveAppLimits =
      'https://help.ardrive.io/hc/en-us/articles/5300389777179-ArDrive-App-';
  static const priceCalculatorLink = 'https://prices.ardrive.io/';
  static const docsLink = 'https://docs.ar.io/build/advanced/arfs';
  static const arnsLink = 'https://arns.ar.io/';
  static const arnsArcssLink = 'https://docs.ar.io/learn/wayfinder';
}

class Images {
  const Images();

  final brand = const Brand();
  final Login login = const Login();
  final icons = const _Icons();
}

class Brand {
  const Brand();
  final logo1 = 'assets/images/brand/1x.png';

  final whiteLogo1 = 'assets/images/brand/white_logo_1x.png';
  final whiteLogo2 = 'assets/images/brand/white_logo_2x.png';

  final blackLogo1 = 'assets/images/brand/black_logo_1x.png';
  final blackLogo2 = 'assets/images/brand/black_logo_2x.png';
  final turboWhite = 'assets/images/brand/turbo-white.svg';
  final turboBlack = 'assets/images/brand/turbo-black.svg';
}

class Login {
  const Login();

  final String ardriveLogoOnboarding = 'assets/images/brand/2x.png';
  final String wanderLogo = 'assets/images/login/wander.svg';
  final String lattice = 'assets/images/login/lattice.svg';
  final String latticeLight = 'assets/images/login/lattice_light.svg';
  final String latticeLarge = 'assets/images/login/lattice_large.svg';
  final String latticeLargeLight =
      'assets/images/login/lattice_large_light.svg';
  final String confetti = 'assets/images/login/confetti.png';
  final String confettiLeft = 'assets/images/login/confetti_left.png';
  final String confettiRight = 'assets/images/login/confetti_right.png';
  final String arrowRed = 'assets/images/login/arrow_red.svg';
  final String ardriveLoader =
      'assets/animations/ardrive_plates_animation.json';

  final String checkCircle = 'assets/images/login/check_circle.png';
  final String whatIsAKeyfile = 'assets/images/login/what_is_a_keyfile.png';
  final String aboutSecurity = 'assets/images/login/about_security.png';

  final String metamask = 'assets/images/login/metamask_logo_flat.svg';
  final String walletUpload = 'assets/images/login/wallet_upload.svg';

  final BentoBox bentoBox = const BentoBox();

  final String bannerLightMode = 'assets/images/login/banner_light_mode.svg';
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
  final String particleSpace =
      'assets/images/login/bento_box/particle_space.png';
  final String dataStorage = 'assets/images/login/bento_box/data_storage.svg';
  final String bento2 = 'assets/images/login/bento_box/bento-2.svg';
  final String bento2Bg = 'assets/images/login/bento_box/bento-2-bg.svg';
  final String bentoBox2LightMode =
      'assets/images/login/bento_box/bento-box-2-light-mode.svg';
  final String bentoBox2DarkMode =
      'assets/images/login/bento_box/bento-box-2-dark-mode.svg';

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
