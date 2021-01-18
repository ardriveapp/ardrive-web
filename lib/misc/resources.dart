class R {
  static final images = Images();
}

class Images {
  const Images();

  final brand = const Brand();
  final profile = const Profile();
}

class Brand {
  const Brand();

  final logoHorizontalNoSubtitle =
      'assets/images/brand/logo-horiz-beta-no-subtitle.png';
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
