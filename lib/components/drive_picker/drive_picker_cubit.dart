import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/mime_lookup.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A folder or a file as the drive picker lists it.
class DrivePickerEntry extends Equatable {
  const DrivePickerEntry({
    required this.id,
    required this.name,
    required this.contentType,
    this.isPinned = false,
  });

  final String id;
  final String name;

  /// `folder` for a folder, else the file's type, as the explorer's icons
  /// read it.
  final String contentType;

  /// A pinned file's data is someone else's.
  final bool isPinned;

  bool get isFolder => contentType == 'folder';

  @override
  List<Object?> get props => [id, name, contentType, isPinned];
}

/// A folder's visible contents, folders first, in the explorer's order.
class DrivePickerFolder extends Equatable {
  const DrivePickerFolder({
    required this.id,
    required this.name,
    required this.parentFolderId,
    required this.folders,
    required this.files,
  });

  final String id;
  final String name;

  /// Null at the drive's root.
  final String? parentFolderId;
  final List<DrivePickerEntry> folders;
  final List<DrivePickerEntry> files;

  @override
  List<Object?> get props => [id, name, parentFolderId, folders, files];
}

/// Reads [folderId] of [drive], its root when null. Null when it is not on
/// this device.
typedef DrivePickerRead = Future<DrivePickerFolder?> Function(
  Drive drive,
  String? folderId,
);

/// [DrivePickerRead] from the local database, in the explorer's natural name
/// order. Hidden items are left out: hiding something is asking not to see
/// it, and nothing hidden can be published.
DrivePickerRead drivePickerReadFrom(DriveDao driveDao) =>
    (drive, folderId) async {
      try {
        final folder = await driveDao
            .folderById(folderId: folderId ?? drive.rootFolderId)
            .getSingleOrNull();
        // A drive nothing on this device has read has no root folder yet.
        if (folder == null || folder.driveId != drive.id) return null;
        final folders = await driveDao
            .foldersInFolder(driveId: drive.id, parentFolderId: folder.id)
            .get();
        final files = await driveDao
            .filesInFolder(driveId: drive.id, parentFolderId: folder.id)
            .get();
        int byName(DrivePickerEntry a, DrivePickerEntry b) =>
            compareAlphabeticallyAndNatural(a.name, b.name);
        return DrivePickerFolder(
          id: folder.id,
          name: folder.name,
          parentFolderId:
              folder.id == drive.rootFolderId ? null : folder.parentFolderId,
          folders: [
            for (final folder in folders)
              if (!folder.isHidden)
                DrivePickerEntry(
                  id: folder.id,
                  name: folder.name,
                  contentType: 'folder',
                ),
          ]..sort(byName),
          files: [
            for (final file in files)
              if (!file.isHidden)
                DrivePickerEntry(
                  id: file.id,
                  name: file.name,
                  contentType: switch (file.dataContentType) {
                    final type? when type.isNotEmpty => type,
                    _ => lookupMimeType(file.name) ?? '',
                  },
                  isPinned: file.pinnedDataOwnerAddress != null,
                ),
          ]..sort(byName),
        );
      } catch (e) {
        logger.d('[drive picker] folder could not be read: $e');
        return null;
      }
    };

class DrivePickerState extends Equatable {
  const DrivePickerState({
    required this.drives,
    this.drive,
    this.folder,
    this.fileId,
    this.loading = false,
  });

  /// The drives to choose from.
  final List<Drive> drives;

  /// The drive open in the picker; null while choosing a drive.
  final Drive? drive;

  /// [drive]'s folder in view; null while it loads, or when [drive] is not
  /// on this device yet.
  final DrivePickerFolder? folder;

  /// The file chosen in [folder], where files can be chosen.
  final String? fileId;
  final bool loading;

  bool get choosingDrive => drive == null;

  /// [drive] is open but its folder could not be read.
  bool get unreadable => drive != null && !loading && folder == null;

  bool get atRoot => folder != null && folder!.parentFolderId == null;

  @override
  List<Object?> get props => [drives, drive, folder, fileId, loading];
}

/// Walks the user's drives and folders for the drive picker.
class DrivePickerCubit extends Cubit<DrivePickerState> {
  DrivePickerCubit({
    required List<Drive> drives,
    required DrivePickerRead read,
  })  : _read = read,
        super(DrivePickerState(drives: drives));

  final DrivePickerRead _read;

  /// Counts reads, so a slow one that lost a race lands nowhere.
  int _reads = 0;

  /// Opens on [driveId]'s [folderId], or its root; on the list of drives
  /// when [driveId] is not one of them.
  Future<void> start({String? driveId, String? folderId}) async {
    final drive = _driveById(driveId);
    if (drive == null) return;
    await _open(drive, folderId);
    // A folder that has gone (moved, or hidden) opens the drive's root.
    if (folderId != null && state.drive == drive && state.folder == null) {
      await _open(drive, null);
    }
  }

  Future<void> openDrive(Drive drive) => _open(drive, null);

  Future<void> openFolder(String folderId) {
    final drive = state.drive;
    if (drive == null) return Future.value();
    return _open(drive, folderId);
  }

  /// Up a folder, or from a drive's root (or a drive that could not be
  /// read) back to the drives.
  Future<void> back() {
    final drive = state.drive;
    final parent = state.folder?.parentFolderId;
    if (drive == null) return Future.value();
    if (parent == null) {
      _reads++;
      emit(DrivePickerState(drives: state.drives));
      return Future.value();
    }
    return _open(drive, parent);
  }

  /// Chooses the file [fileId], or lets it go when it is chosen already.
  void chooseFile(String fileId) {
    emit(DrivePickerState(
      drives: state.drives,
      drive: state.drive,
      folder: state.folder,
      fileId: state.fileId == fileId ? null : fileId,
    ));
  }

  Drive? _driveById(String? driveId) {
    for (final drive in state.drives) {
      if (drive.id == driveId) return drive;
    }
    return null;
  }

  Future<void> _open(Drive drive, String? folderId) async {
    final read = ++_reads;
    emit(DrivePickerState(drives: state.drives, drive: drive, loading: true));
    final folder = await _read(drive, folderId);
    if (isClosed || read != _reads) return;
    emit(DrivePickerState(drives: state.drives, drive: drive, folder: folder));
  }
}
