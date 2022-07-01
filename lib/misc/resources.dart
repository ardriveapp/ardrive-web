class R {
  static final images = Images();
  static const arHelpLink =
      'https://ardrive.io/questions/where-do-i-get-additional-arweave-tokens/';
  static const manifestLearnMoreLink =
      'https://ardrive.atlassian.net/wiki/spaces/help/pages/359530513/Arweave+Manifests';
  static const infernoRulesLink = 'https://ardrive.io/inferno/';
  static const helpLink = 'https://ardrive.zendesk.com/';
}

class Images {
  const Images();

  final brand = const Brand();
  final profile = const Profile();
  final inferno = const Inferno();
}

class Brand {
  const Brand();

  final logoHorizontalNoSubtitle =
      'assets/images/brand/logo-horiz-no-subtitle.png';
  final logoHorizontalNoSubtitleDark =
      'assets/images/brand/logo-horiz-no-subtitle-dark.png';
  final logoHorizontalNoSubtitleLight =
      'assets/images/brand/logo-horiz-no-subtitle-light.png';
  final logoVerticalNoSubtitle =
      'assets/images/brand/logo-vert-no-subtitle.png';
}

class Profile {
  const Profile();

  final profileAdd = 'assets/images/profile/profile_add.png';
  final profileOnboarding = 'assets/images/profile/profile_onboarding.png';
  final profileUnlock = 'assets/images/profile/profile_unlock.png';
  final profileWelcome = 'assets/images/profile/profile_welcome.png';

  final permahillsBg = 'assets/images/profile/profile_permahills_bg.png';

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
