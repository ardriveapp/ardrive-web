class Resources {
  static const images = Images();

  static const ardrivePublicSiteLink = 'https://ardrive.io/';
  static const agreementLink = 'https://ardrive.io/tos-and-privacy/';
  static const getWalletLink = 'https://www.wander.app/';
  static const manifestLearnMoreLink =
      'https://docs.ar.io/build/upload/manifests';

  static const emailSupport = 'support@ardrive.io';
  static const helpCenterLink = 'https://ardrive.io/help/';
  static const discordLink = 'https://discord.gg/KkTqDe4GAF';

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
}

class Login {
  const Login();

  final String wanderLogo = 'assets/images/login/wander.svg';
  final String lattice = 'assets/images/login/lattice.svg';
  final String latticeLight = 'assets/images/login/lattice_light.svg';
  final String confetti = 'assets/images/login/confetti.png';
  final String ardriveLoader =
      'assets/animations/ardrive_plates_animation.json';

  final String checkCircle = 'assets/images/login/check_circle.png';
  final String whatIsAKeyfile = 'assets/images/login/what_is_a_keyfile.png';
  final String aboutSecurity = 'assets/images/login/about_security.png';

  final String metamask = 'assets/images/login/metamask_logo_flat.svg';
  final String solana = 'assets/images/login/solana_logo.png';
  final String phantom = 'assets/images/login/phantom_logo.svg';
  final String solflare = 'assets/images/login/solflare_logo.png';

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
  final String particleSpace =
      'assets/images/login/bento_box/particle_space.png';
  final String dataStorage = 'assets/images/login/bento_box/data_storage.svg';

  /// A feature slide's art, faded into a dark or a light tile. Shapes from
  /// Phosphor Icons (MIT), see `assets/images/login/bento_box/LICENSES.md`.
  String featureArt(String name, {required bool light}) =>
      'assets/images/login/bento_box/$name${light ? '_light' : ''}.svg';

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
