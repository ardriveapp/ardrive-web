import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_secret_source.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:cryptography/cryptography.dart';
import 'package:rxdart/rxdart.dart';

/// What the profile keeps about this device's key: never the key itself.
class DeviceRecord {
  const DeviceRecord({
    required this.method,
    required this.deviceSalt,
    this.keyCheck,
  });

  final DeviceUnlockMethod method;
  final Uint8List deviceSalt;

  /// See [makeKeyCheck]. Null until the first device key is made for a
  /// profile that was saved without one.
  final Uint8List? keyCheck;
}

enum DeviceUnlockStatus {
  /// [DeviceUnlockOutcome.key] opens what this device remembers.
  unlocked,

  /// Nothing is remembered, so nobody was asked.
  nothingRemembered,

  /// The person said no, or Wander couldn't be reached. Drives stay locked.
  declined,

  /// The wallet signed, but not as it did before: its key opens nothing.
  /// Drives stay locked; nothing wrong is ever read.
  mismatch,

  /// The wallet couldn't sign.
  failed,
}

class DeviceUnlockOutcome {
  const DeviceUnlockOutcome(this.status, [this.key]);

  final DeviceUnlockStatus status;
  final SecretKey? key;

  bool get unlocked => key != null;
}

/// The session's device key, asked for at most once per session.
///
/// - **Reading** ([unlockToRead]): only when something is remembered. A
///   session with nothing remembered never shows a wallet prompt for it.
/// - **Remembering** ([unlockToRemember]): a new remembered key needs the
///   device key to wrap it, so this may ask when nothing was remembered yet.
///
/// Either way the wallet is asked once per session at most. A prompt that is
/// cancelled, or a wallet whose signature doesn't match the key check, is
/// the answer for the rest of the session: remembered drives stay locked,
/// and new ones are kept for this session only. Two callers at once share
/// one request.
///
/// A password account's key is derived where the password is typed and
/// handed over with [adopt]; nothing here asks for it.
///
/// Memory only. Signing out calls [clear].
class DeviceUnlocker {
  SecretKey? _key;
  DeviceUnlockOutcome? _settled;
  int _generation = 0;
  Future<DeviceUnlockOutcome>? _inFlight;
  final _waitingOnWallet = BehaviorSubject<bool>.seeded(false);

  /// The device key, once this session has it.
  SecretKey? get key => _key;

  /// True while a wallet prompt for the device key is open, for the line
  /// "Approve in Wander to open your drives".
  Stream<bool> get waitingOnWallet => _waitingOnWallet.stream.distinct();

  bool get isWaitingOnWallet => _waitingOnWallet.value;

  /// Whether the wallet was already asked this session, whatever it said.
  bool get asked => _settled != null;

  /// Takes a device key made elsewhere: the device password's, when the
  /// person signs in with it.
  void adopt(SecretKey key) {
    _key = key;
    _settled = DeviceUnlockOutcome(DeviceUnlockStatus.unlocked, key);
  }

  Future<DeviceUnlockOutcome> unlockToRead({
    required DeviceRecord record,
    required DeviceSecretSource source,
    required Future<bool> Function() hasRemembered,
  }) async {
    final key = _key;
    if (key != null) {
      return DeviceUnlockOutcome(DeviceUnlockStatus.unlocked, key);
    }
    if (_settled == null && _inFlight == null && !await hasRemembered()) {
      return const DeviceUnlockOutcome(DeviceUnlockStatus.nothingRemembered);
    }
    return _askOnce(record, source, null);
  }

  /// [saveKeyCheck] stores the key check of a profile that has none yet.
  Future<DeviceUnlockOutcome> unlockToRemember({
    required DeviceRecord record,
    required DeviceSecretSource source,
    Future<void> Function(Uint8List keyCheck)? saveKeyCheck,
  }) async {
    final key = _key;
    if (key != null) {
      return DeviceUnlockOutcome(DeviceUnlockStatus.unlocked, key);
    }
    return _askOnce(record, source, saveKeyCheck);
  }

  Future<DeviceUnlockOutcome> _askOnce(
    DeviceRecord record,
    DeviceSecretSource source,
    Future<void> Function(Uint8List keyCheck)? saveKeyCheck,
  ) {
    final settled = _settled;
    if (settled != null) return Future.value(settled);
    final generation = _generation;

    Future<DeviceUnlockOutcome> ask() async {
      try {
        final outcome = await _ask(record, source, saveKeyCheck);
        // Signed out while the wallet was asked: the answer belongs to a
        // session that is over.
        if (generation != _generation) return outcome;
        _settled = outcome;
        if (outcome.key != null) _key = outcome.key;
        return outcome;
      } finally {
        // Also when it threw, so the next caller asks again rather than
        // getting the same error for the rest of the session.
        if (generation == _generation) _inFlight = null;
      }
    }

    return _inFlight ??= ask();
  }

  Future<DeviceUnlockOutcome> _ask(
    DeviceRecord record,
    DeviceSecretSource source,
    Future<void> Function(Uint8List keyCheck)? saveKeyCheck,
  ) async {
    if (source.method != record.method) {
      logger.w('Device unlock: the profile uses ${record.method.value}, '
          'not ${source.method.value}');
      return const DeviceUnlockOutcome(DeviceUnlockStatus.failed);
    }

    final Uint8List secret;
    _waitingOnWallet.add(source.method.prompts);
    try {
      secret = await source.secret(record.deviceSalt);
    } on DeviceUnlockDeclined {
      logger.i('Device unlock: the wallet prompt was declined');
      return const DeviceUnlockOutcome(DeviceUnlockStatus.declined);
    } on DeviceUnlockFailed catch (e) {
      logger.w('Device unlock: the wallet could not sign: ${e.reason}');
      return const DeviceUnlockOutcome(DeviceUnlockStatus.failed);
    } catch (e) {
      logger.w('Device unlock: the wallet could not sign: $e');
      return const DeviceUnlockOutcome(DeviceUnlockStatus.failed);
    } finally {
      _waitingOnWallet.add(false);
    }

    final key = await deriveDeviceKey(
      secret: secret,
      deviceSalt: record.deviceSalt,
      method: record.method,
    );

    final keyCheck = record.keyCheck;
    if (keyCheck != null) {
      if (!await keyCheckMatches(key, keyCheck)) {
        logger.w('Device unlock: the wallet signed differently than before; '
            'remembered drives stay locked');
        return const DeviceUnlockOutcome(DeviceUnlockStatus.mismatch);
      }
    } else if (saveKeyCheck != null) {
      await saveKeyCheck(await makeKeyCheck(key));
    } else {
      // Nothing to check against and nowhere to keep a check: the key can't
      // be trusted to open anything.
      return const DeviceUnlockOutcome(DeviceUnlockStatus.failed);
    }

    return DeviceUnlockOutcome(DeviceUnlockStatus.unlocked, key);
  }

  /// Forgets the key and lets the next session ask again. Signing out.
  void clear() {
    _generation++;
    _key = null;
    _settled = null;
    _inFlight = null;
    _waitingOnWallet.add(false);
  }
}
