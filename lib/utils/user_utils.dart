import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/user.dart';

bool isDriveOwner(ArDriveAuth auth, String driveOwner) {
  User user;
  try {
    user = auth.currentUser;
  } catch (e) {
    return false;
  }

  return user.walletAddress == driveOwner;
}
