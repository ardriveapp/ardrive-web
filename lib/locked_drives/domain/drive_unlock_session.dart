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

  /// Replaces [ownerAddress]'s locked drives with [drives], as found by the
  /// newest drive discovery.
  void setLockedDrives(String ownerAddress, Iterable<LockedDrive> drives) {
    final next = [
      for (final drive in _lockedDrives.value)
        if (drive.ownerAddress != ownerAddress) drive,
      ...drives,
    ]..sort((a, b) => a.driveId.compareTo(b.driveId));

    _lockedDrives.add(List.unmodifiable(next));
  }

  /// Takes [driveId] off the locked list, once a key has opened it.
  void markUnlocked(String driveId) {
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

  /// The password bytes that last opened [driveId] this session, if any.
  List<int>? provenPasswordInfo(String driveId) => _provenPasswordInfo[driveId];

  void rememberProvenPasswordInfo(String driveId, List<int> info) =>
      _provenPasswordInfo[driveId] = List.unmodifiable(info);

  /// Forgets everything. Called on sign-out.
  void clear() {
    _signatures.clear();
    _walletDeclined.clear();
    _provenPasswordInfo.clear();
    _lockedDrives.add(const []);
  }
}
