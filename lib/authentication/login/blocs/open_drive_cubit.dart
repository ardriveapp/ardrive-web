import 'dart:async';

import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/drive_link_input.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;

part 'open_drive_state.dart';

/// Opens a drive for somebody who has not signed in.
///
/// The visitor's half of what `DriveAttachCubit` does for a signed-in user:
/// find the drive the pasted text names, ask the chain whether it is public
/// or private, take a drive key when it is private, and write the drive row.
/// It stops short of starting the sync because on the sign-in screen there is
/// no `SyncCubit` yet; the router starts it as it builds the explorer.
///
/// Needs only the gateway and the database, both of which exist above the
/// router, which is why this can run where the attach cubit cannot.
class OpenDriveCubit extends Cubit<OpenDriveState> {
  OpenDriveCubit({
    required ArweaveService arweave,
    required DriveDao driveDao,
    Duration lookupDelay = const Duration(milliseconds: 250),
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _lookupDelay = lookupDelay,
        super(const OpenDriveInitial());

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  /// How long typing has to pause before a lookup goes out. A paste is one
  /// event, so it pays this once; typing an ID by hand does not fire a query
  /// on every character.
  final Duration _lookupDelay;

  Timer? _debounce;

  /// Which input the lookup in flight is for, so a stale answer is dropped.
  int _generation = 0;

  DriveLinkInputDrive? _target;
  DriveEntity? _entity;
  DriveKey? _driveKey;

  /// The text in the first field changed.
  void inputChanged(String raw) {
    _debounce?.cancel();
    final generation = ++_generation;

    _target = null;
    _entity = null;
    _driveKey = null;

    // What was found belongs to the old text. Until the new text is looked
    // up, there is nothing to open, so the button must not offer it.
    if (state.canOpen) {
      emit(const OpenDriveInitial());
    }

    if (raw.trim().isEmpty) {
      _backToStart();
      return;
    }

    _debounce = Timer(_lookupDelay, () => _lookUp(raw, generation));
  }

  /// The first field lost focus. Text that is neither a link nor an ID is
  /// only called out now, not while it is still being typed.
  Future<void> inputBlurred(String raw) async {
    if (raw.trim().isEmpty || state is! OpenDriveInitial) {
      return;
    }

    final generation = _generation;
    final input = await DriveLinkInput.parse(raw);

    if (_isStale(generation) || input is! DriveLinkInputUnrecognised) {
      return;
    }

    // The lookup still waiting on the debounce would only find the same
    // nothing and clear this message.
    _debounce?.cancel();
    emit(const OpenDriveUnrecognisedInput());
  }

  /// The drive key field changed. Only meaningful while a private drive is
  /// waiting for its key.
  void keyChanged(String raw) {
    final current = state;

    if (current is! OpenDrivePrivate) {
      return;
    }

    _debounce?.cancel();
    final generation = ++_generation;

    // The accepted key belonged to the old text. Until the new one is
    // checked, Open must not use it.
    _driveKey = null;

    if (raw.trim().isEmpty || current.keyAccepted) {
      emit(current.copyWith(name: null, keyRejected: false));
    }

    if (raw.trim().isEmpty) {
      return;
    }

    _debounce = Timer(
      _lookupDelay,
      () => _validateKey(current, raw.trim(), generation),
    );
  }

  /// Writes the drive and hands it to whoever opened this dialog.
  Future<void> open() async {
    final current = state;
    final target = _target;
    final entity = _entity;

    if (target == null || entity == null || !current.canOpen) {
      return;
    }

    emit(const OpenDriveOpening());

    try {
      await _driveDao.writeDriveEntity(
        name: entity.name!,
        entity: entity,
        driveKey: _driveKey,
        // No profile, so a private key goes to memory only. The row gets an
        // encrypted copy if the visitor signs in later.
        profileKey: null,
      );

      unawaited(PlausibleEventTracker.trackOpenDriveAsVisitor(
        drivePrivacy:
            _driveKey == null ? DrivePrivacy.public : DrivePrivacy.private,
      ));

      if (isClosed) return;

      emit(OpenDriveOpened(
        driveId: target.driveId,
        folderId: target.folderId,
        driveKey: _driveKey,
      ));
    } catch (e, stackTrace) {
      logger.e('Failed to open drive ${target.driveId}', e, stackTrace);

      if (isClosed) return;

      emit(const OpenDriveFailure());
    }
  }

  Future<void> _lookUp(String raw, int generation) async {
    final input = await DriveLinkInput.parse(raw);

    if (_isStale(generation)) return;

    switch (input) {
      case DriveLinkInputUnrecognised():
        // Not an error yet: they may still be typing. `inputBlurred` says so
        // once they leave the field.
        _backToStart();
        return;
      case DriveLinkInputOtherLink():
        emit(OpenDriveOtherLink(route: input.route, isFile: input.isFile));
        return;
      case DriveLinkInputDrive():
        break;
    }

    _target = input;
    emit(const OpenDriveLookingUp());

    try {
      final found = await _arweave.getDrivePrivacyForId(input.driveId);

      if (_isStale(generation)) return;

      if (found == null || found.privacy == null) {
        emit(const OpenDriveNotFound());
        return;
      }

      if (found.privacy == DrivePrivacyTag.private) {
        final linkKey = input.rawDriveKey;

        if (linkKey != null && input.driveKey != null) {
          // The link brought its own key. Validate it the same way a typed
          // one is, and show it filled so the reader sees why it opened.
          await _validateKey(
            OpenDrivePrivate(
              driveId: input.driveId,
              prefilledKey: linkKey,
            ),
            linkKey,
            generation,
          );
          return;
        }

        emit(OpenDrivePrivate(driveId: input.driveId));
        return;
      }

      final entity = await _arweave.getLatestDriveEntityWithId(
        input.driveId,
        driveOwner: found.ownerAddress,
      );

      if (_isStale(generation)) return;

      if (entity == null) {
        emit(const OpenDriveNotFound());
        return;
      }

      _entity = entity;
      emit(OpenDrivePublic(driveId: input.driveId, name: entity.name!));
    } catch (e) {
      logger.e('Error looking up drive ${input.driveId}', e);

      if (_isStale(generation)) return;

      emit(const OpenDriveNetworkError());
    }
  }

  Future<void> _validateKey(
    OpenDrivePrivate current,
    String rawKey,
    int generation,
  ) async {
    final DriveKey key;
    try {
      key = DriveKey(SecretKey(decodeBase64ToBytes(rawKey)), true);
    } catch (_) {
      if (_isStale(generation)) return;
      emit(current.copyWith(name: null, keyRejected: true, validating: false));
      return;
    }

    emit(current.copyWith(name: null, keyRejected: false, validating: true));

    try {
      final entity = await _arweave.getLatestDriveEntityWithId(
        current.driveId,
        driveKey: key.key,
      );

      if (_isStale(generation)) return;

      if (entity == null) {
        _driveKey = null;
        emit(current.copyWith(
          name: null,
          keyRejected: true,
          validating: false,
        ));
        return;
      }

      _entity = entity;
      _driveKey = key;
      emit(current.copyWith(
        name: entity.name,
        keyRejected: false,
        validating: false,
      ));
    } catch (e) {
      logger.e('Error validating the key for drive ${current.driveId}', e);

      if (_isStale(generation)) return;

      emit(const OpenDriveNetworkError());
    }
  }

  /// Back to the empty state, unless that is where we are. A cubit's very
  /// first emit goes through even when the state is equal, so without the
  /// check a field cleared before anything was found would emit a duplicate.
  void _backToStart() {
    if (state is! OpenDriveInitial) {
      emit(const OpenDriveInitial());
    }
  }

  bool _isStale(int generation) => isClosed || generation != _generation;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
