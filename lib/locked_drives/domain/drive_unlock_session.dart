import 'dart:typed_data';

import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:rxdart/rxdart.dart';

/// What this session knows about opening the user's private drives, kept in
/// memory and nowhere else.
///
/// - The drives it can't open ([lockedDrives]).
/// - Each drive's wallet signature, so trying a second password, or one
///   password on several drives, never asks the wallet twice. The v1 and v2
///   signatures don't depend on the password.
/// - The drives whose wallet prompt was cancelled, so a background sync doesn't
///   ask again until the user does something (unlocks, or syncs by hand).
/// - The password bytes proven to open each drive, which the v1 drive
///   migration must use rather than the sign-in password.
/// - Whether the wallet's one-approval batch signing can be used.
///
/// None of it is ever written to storage. Signing out calls [clear]. A future
/// "remember on this device" stores wrapped drive keys, never these.
class DriveUnlockSession {
  final _lockedDrives = BehaviorSubject<List<LockedDrive>>.seeded(const []);

  final _signatures = <String, Uint8List>{};
  final _walletDeclined = <String>{};
  final _provenPasswordInfo = <String, List<int>>{};

  /// The drives the session can't open, by drive ID: they have no name to
  /// sort by, and the drives list orders them the same way. See [LockedDrive].
  Stream<List<LockedDrive>> get lockedDrives => _lockedDrives.stream;

  List<LockedDrive> get currentLockedDrives => _lockedDrives.value;

  bool isLocked(String driveId) =>
      _lockedDrives.value.any((drive) => drive.driveId == driveId);

  LockedDrive? lockedDrive(String driveId) {
    for (final drive in _lockedDrives.value) {
      if (drive.driveId == driveId) {
        return drive;
      }
    }

    return null;
  }

  /// Counts unlocks, so a discovery pass can tell which happened after it
  /// started. See [setLockedDrives].
  int _unlockGeneration = 0;
  final _unlockedAt = <String, int>{};

  /// Read when a discovery pass starts, and handed back to [setLockedDrives].
  int get unlockGeneration => _unlockGeneration;

  /// Replaces [ownerAddress]'s locked drives with [drives], as found by the
  /// newest drive discovery.
  ///
  /// [since] is the [unlockGeneration] the pass started at. A drive unlocked
  /// after that was read as locked by a pass that didn't know yet, and is
  /// left unlocked.
  void setLockedDrives(
    String ownerAddress,
    Iterable<LockedDrive> drives, {
    int? since,
  }) {
    final next = [
      for (final drive in _lockedDrives.value)
        if (drive.ownerAddress != ownerAddress) drive,
      for (final drive in drives)
        if (since == null || (_unlockedAt[drive.driveId] ?? 0) <= since) drive,
    ]..sort((a, b) => a.driveId.compareTo(b.driveId));

    _lockedDrives.add(List.unmodifiable(next));
  }

  /// Takes [driveId] off the locked list, once a key has opened it.
  void markUnlocked(String driveId) {
    _unlockedAt[driveId] = ++_unlockGeneration;

    if (!isLocked(driveId)) {
      return;
    }

    _lockedDrives.add(List.unmodifiable([
      for (final drive in _lockedDrives.value)
        if (drive.driveId != driveId) drive,
    ]));
  }

  static String _key(
    String ownerAddress,
    String driveId, [
    DriveSignatureType? type,
  ]) =>
      '$ownerAddress/$driveId${type == null ? '' : '/${type.value}'}';

  Uint8List? signature(
    String ownerAddress,
    String driveId,
    DriveSignatureType type,
  ) =>
      _signatures[_key(ownerAddress, driveId, type)];

  void rememberSignature(
    String ownerAddress,
    String driveId,
    DriveSignatureType type,
    Uint8List signature,
  ) {
    _signatures[_key(ownerAddress, driveId, type)] = signature;
    _walletDeclined.remove(_key(ownerAddress, driveId));
  }

  /// Whether a wallet signature for [driveId], of either type, is held: so
  /// trying a password on it asks the wallet nothing.
  bool holdsSignatureFor(String ownerAddress, String driveId) =>
      DriveSignatureType.values
          .any((type) => signature(ownerAddress, driveId, type) != null);

  bool walletDeclined(String ownerAddress, String driveId) =>
      _walletDeclined.contains(_key(ownerAddress, driveId));

  void markWalletDeclined(String ownerAddress, String driveId) =>
      _walletDeclined.add(_key(ownerAddress, driveId));

  /// Lets the wallet be asked again: for every drive after a sync the user
  /// started, or for one drive the user chose to unlock.
  void forgetWalletDeclined({String? ownerAddress, String? driveId}) {
    if (ownerAddress == null || driveId == null) {
      _walletDeclined.clear();
      return;
    }

    _walletDeclined.remove(_key(ownerAddress, driveId));
  }

  final _batchSigningUnusable = <String>{};

  /// Whether signing several drives in one wallet approval failed for
  /// [ownerAddress] this session in a way asking again won't fix: Wander
  /// refused it (a hardware wallet), or its signatures didn't match the
  /// ones it gives one at a time. Its drives are then asked for one by one.
  bool batchSigningUnusable(String ownerAddress) =>
      _batchSigningUnusable.contains(ownerAddress);

  void markBatchSigningUnusable(String ownerAddress) =>
      _batchSigningUnusable.add(ownerAddress);

  final _signInPasswordProven = <String, bool>{};

  /// Whether the password this session signed in with opened one of
  /// [ownerAddress]'s private drives: true if it did (or there were none to
  /// open), false if it opened none and the user chose to continue, null if
  /// the session didn't sign in through that check (Welcome back).
  ///
  /// False means the password may be a typo. It is then not tried again on
  /// the wallet's behalf at the cost of a prompt, and not used to make a new
  /// private drive's key.
  bool? signInPasswordProven(String ownerAddress) =>
      _signInPasswordProven[ownerAddress];

  void setSignInPasswordProven(String ownerAddress, bool proven) =>
      _signInPasswordProven[ownerAddress] = proven;

  final _newDrivePassword = <String, String>{};
  final _provenDrivePassword = <String, String>{};

  /// The password new private drives are made with while the sign-in
  /// password is unproven: only what the user typed into Create drive's
  /// "Enter your drive password", once it opened one of their drives. So it
  /// is asked once, not for every new drive. Unlocking a drive never sets
  /// it: an old drive's password (a CLI drive's, say) is not the drive
  /// password.
  String? newDrivePassword(String ownerAddress) =>
      _newDrivePassword[ownerAddress];

  void setNewDrivePassword(String ownerAddress, String password) =>
      _newDrivePassword[ownerAddress] = password;

  final _provenDrivePasswordKeepsKeys = <String, bool>{};

  /// The last password that opened one of [ownerAddress]'s drives this
  /// session, from Create drive, or from Unlock with "Try on my other locked
  /// drives" ticked. Discovery tries it while the sign-in password is
  /// unproven: each attempt is proven by opening a drive. Never used to make
  /// a drive.
  String? provenDrivePassword(String ownerAddress) =>
      _provenDrivePassword[ownerAddress];

  /// Whether the drives discovery opens with [provenDrivePassword] have their
  /// key stored on this device: the "Remember on this device" choice made
  /// with that password. Without it they are kept for this session only.
  bool provenDrivePasswordKeepsKeys(String ownerAddress) =>
      _provenDrivePasswordKeepsKeys[ownerAddress] ?? true;

  void rememberProvenDrivePassword(
    String ownerAddress,
    String password, {
    bool keepKeys = true,
  }) {
    _provenDrivePassword[ownerAddress] = password;
    _provenDrivePasswordKeepsKeys[ownerAddress] = keepKeys;
  }

  /// The password bytes that last opened [driveId] this session, if any.
  List<int>? provenPasswordInfo(String driveId) => _provenPasswordInfo[driveId];

  void rememberProvenPasswordInfo(String driveId, List<int> info) =>
      _provenPasswordInfo[driveId] = List.unmodifiable(info);

  /// Forgets everything. Called on sign-out.
  void clear() {
    _signatures.clear();
    _walletDeclined.clear();
    _batchSigningUnusable.clear();
    _provenPasswordInfo.clear();
    _signInPasswordProven.clear();
    _newDrivePassword.clear();
    _provenDrivePassword.clear();
    _provenDrivePasswordKeepsKeys.clear();
    _unlockedAt.clear();
    _lockedDrives.add(const []);
  }
}
