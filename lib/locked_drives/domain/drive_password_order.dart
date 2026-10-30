import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

/// When ArDrive 3.0, which decoupled drive passwords from signing in, was
/// planned to ship. Set it to the release's deploy date when it ships.
///
/// Before 3.0 a private drive's password was the account's sign-in password
/// in practice: web always used it, and the CLI made every drive use the
/// first drive's. Only desktop let each drive have its own. So a drive made
/// before this date most likely opens with the password that opened the
/// others. Only the order passwords are tried in depends on it: a drive that
/// doesn't open still shows as locked, whatever this says.
final drivePasswordEraCutoff = DateTime.utc(2026, 11, 1);

/// The `App-Name` of ArDrive desktop, the one app that let each private
/// drive have its own password.
const _perDrivePasswordApps = {'ArDrive-Desktop'};

/// Which drives to try a password on first: lower first.
///
/// 0. Made before [drivePasswordEraCutoff] by an app that used one password
///    for every drive (web, the CLI, core-js).
/// 1. Made before it by desktop, which allowed a password per drive.
/// 2. Made since.
///
/// [appName] is the drive transaction's `App-Name`. It names the app that
/// wrote that revision, which is not always the one that made the drive, so
/// it only breaks ties within the era.
int drivePasswordTryRank({required DateTime createdAt, String? appName}) {
  if (!createdAt.isBefore(drivePasswordEraCutoff)) return 2;
  return _perDrivePasswordApps.contains(appName) ? 1 : 0;
}

/// Orders drive transactions for trying one password on them: by
/// [drivePasswordTryRank], then oldest first. [createdAt] gives a drive's
/// creation time, the best one known.
int compareForPasswordTries(
  TransactionCommonMixin a,
  TransactionCommonMixin b,
  DateTime Function(TransactionCommonMixin tx) createdAt,
) {
  final createdA = createdAt(a);
  final createdB = createdAt(b);
  final byRank = drivePasswordTryRank(
          createdAt: createdA, appName: a.getTag(EntityTag.appName))
      .compareTo(drivePasswordTryRank(
          createdAt: createdB, appName: b.getTag(EntityTag.appName)));
  return byRank != 0 ? byRank : createdA.compareTo(createdB);
}
