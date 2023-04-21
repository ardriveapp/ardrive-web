import 'package:ardrive/authentication/ardrive_auth.dart';

bool isDriveOwner(ArDriveAuth auth, String driveOwner) {
  if (auth.currentUser == null) {
    return false;
  }

  return auth.currentUser!.walletAddress == driveOwner;
}
