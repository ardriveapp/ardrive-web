import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'drive_share_state.dart';

/// [DriveShareCubit] includes logic for the user to retrieve a link to share a public drive with.
class DriveShareCubit extends Cubit<DriveShareState> {
  final Drive drive;

  /// The folder being shared, or `null` when the whole drive is.
  final FolderID? folderId;

  /// The folder's own name, for the dialog to confirm what is being shared.
  final String? folderName;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  /// Whether the built link embeds the drive key.
  ///
  /// Starts off. See [generatePrivateDriveShareLink] for why a drive key is
  /// handed over separately by default.
  bool _keyIsInLink = false;

  /// Which load is current. A load that is not the newest by the time it
  /// finishes has been overtaken and must not emit - the same generation guard
  /// [SharedFileCubit] uses.
  int _generation = 0;

  DriveShareCubit({
    required this.drive,
    this.folderId,
    this.folderName,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
  })  : _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(DriveShareLoadInProgress()) {
    loadDriveShareDetails();
  }

  /// Rebuilds the link with or without the key embedded in it.
  Future<void> setKeyIsInLink(bool value) async {
    if (value == _keyIsInLink) {
      return;
    }

    _keyIsInLink = value;

    await loadDriveShareDetails();
  }

  /// Builds the share link for [drive], or fails in a way the dialog can show.
  ///
  /// Everything here runs inside the guard on purpose. This method is called
  /// from the constructor body and its future is never awaited, so anything it
  /// throws becomes an unhandled asynchronous error: the cubit would stay in
  /// [DriveShareLoadInProgress] and the dialog would spin forever, which is
  /// exactly what a missing drive key used to do.
  Future<void> loadDriveShareDetails() async {
    final generation = ++_generation;

    // Captured once. Read twice - once to build the link and once to describe
    // it - two loads racing after a fast double-toggle could emit a link built
    // with the key in it while labelling it keyless, and the dialog would then
    // render a key-bearing link unmasked.
    final keyIsInLink = _keyIsInLink;

    emit(DriveShareLoadInProgress());

    try {
      final driveKey = drive.isPrivate ? await _driveKey() : null;

      final driveShareLink = driveKey == null
          ? generatePublicDriveShareLink(
              driveId: drive.id,
              driveName: drive.name,
              folderId: folderId,
            )
          : await generatePrivateDriveShareLink(
              driveId: drive.id,
              driveKey: driveKey.key,
              folderId: folderId,
              includeKey: keyIsInLink,
            );

      // Extracted before the guard so that no await sits between the checks
      // below and the emit.
      final driveKeyBase64 = driveKey == null
          ? null
          : encodeBytesToBase64(await driveKey.key.extractBytes());

      if (isClosed || generation != _generation) {
        return;
      }

      emit(
        DriveShareLoadSuccess(
          drive: drive,
          driveShareLink: driveShareLink,
          isFolder: folderId != null,
          folderName: folderName,
          keyIsInLink: keyIsInLink,
          // The key is offered as its own artifact so the sharer can send it
          // through a different channel than the link.
          driveKeyBase64: driveKeyBase64,
        ),
      );
    } catch (e, stacktrace) {
      // The drive id is safe to log; the key never is, and nothing here puts
      // one in the message.
      logger.e(
        'Failed to build the share link for drive ${drive.id}',
        e,
        stacktrace,
      );

      if (isClosed || generation != _generation) {
        return;
      }

      emit(const DriveShareLoadFail());
    }
  }

  /// The private drive's key, which the link and the handover both need.
  ///
  /// It comes from the profile when one is signed in, and from the in-memory
  /// store otherwise - a drive attached in this session but never persisted.
  /// Neither is guaranteed, and a [StateError] here is a real outcome rather
  /// than a should-never-happen: it lands on the failure state above.
  Future<DriveKey> _driveKey() async {
    final profileState = _profileCubit.state;

    final driveKey = profileState is ProfileLoggedIn
        ? await _driveDao.getDriveKey(drive.id, profileState.user.cipherKey)
        : await _driveDao.getDriveKeyFromMemory(drive.id);

    if (driveKey == null) {
      throw StateError('Drive key not found');
    }

    return driveKey;
  }
}
