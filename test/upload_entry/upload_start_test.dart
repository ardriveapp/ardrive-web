import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/upload_entry/domain/upload_start.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Loaded extends Mock implements DriveDetailLoadSuccess {}

class _Folder extends Mock implements FolderWithContents {}

class _FolderEntry extends Mock implements FolderEntry {}

Drive _drive(String id) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: id,
      privacy: 'private',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// What pressing Upload does, from each place it can be pressed.
void main() {
  final photos = _drive('photos');
  final website = _drive('website');

  DriveDetailLoadSuccess loaded(Drive drive, {String folderId = 'folder'}) {
    final entry = _FolderEntry();
    when(() => entry.id).thenReturn(folderId);

    final folder = _Folder();
    when(() => folder.folder).thenReturn(entry);

    final state = _Loaded();
    when(() => state.currentDrive).thenReturn(drive);
    when(() => state.folderInView).thenReturn(folder);
    return state;
  }

  DrivesLoadSuccess drives(
    List<Drive> owned, {
    String? selected,
    List<Drive> shared = const [],
  }) =>
      DrivesLoadSuccess(
        selectedDriveId: selected,
        userDrives: owned,
        sharedDrives: shared,
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      );

  UploadStart decide({
    DriveDetailState? detailState,
    bool showingDrivesList = false,
    String? openDriveId,
    DrivesState? drivesState,
  }) =>
      decideUploadStart(
        detailState: detailState ?? DriveDetailLoadInProgress(),
        showingDrivesList: showingDrivesList,
        openDriveId: openDriveId,
        drivesState: drivesState ?? drives([photos]),
      );

  group('inside a drive', () {
    test('an open one uploads to the folder in view, as it always has', () {
      final step = decide(
        detailState: loaded(photos, folderId: 'holidays'),
        openDriveId: photos.id,
      );

      expect(
        step,
        isA<UploadHere>()
            .having((s) => s.driveId, 'drive', photos.id)
            .having((s) => s.folderId, 'folder', 'holidays'),
      );
    });

    test('an unsynced one waits with the reader, record in hand', () {
      final step = decide(
        detailState: DriveDetailLoadUnsynced(drive: photos),
        openDriveId: photos.id,
      );

      expect(
        step,
        isA<UploadWhenOpen>()
            .having((s) => s.driveId, 'drive', photos.id)
            .having((s) => s.drive, 'record', photos),
      );
    });

    test('one still opening waits too, and reads its record by id', () {
      final step = decide(openDriveId: photos.id);

      expect(
        step,
        isA<UploadWhenOpen>()
            .having((s) => s.driveId, 'drive', photos.id)
            .having((s) => s.drive, 'record', isNull),
      );
    });

    test('an explorer showing no drive at all falls back to choosing one', () {
      expect(decide(openDriveId: rootPath), isA<UploadIntoDrive>());
      expect(decide(), isA<UploadIntoDrive>());
    });
  });

  group('on the drives list', () {
    /// The cubit the list provides is built against no drive, so what it says
    /// cannot be where the reader is.
    test("ignores the list's own drive page state", () {
      final step = decide(
        detailState: loaded(photos),
        showingDrivesList: true,
        drivesState: drives([photos, website]),
      );

      expect(step, isA<UploadChooseDrive>());
    });

    test('opens the only drive there is', () {
      final step = decide(showingDrivesList: true);

      expect(
        step,
        isA<UploadIntoDrive>().having((s) => s.drive, 'drive', photos),
      );
    });

    test('asks which drive when there are several, last used first', () {
      final step = decide(
        showingDrivesList: true,
        drivesState: drives([photos, website], selected: website.id),
      );

      expect(
        step,
        isA<UploadChooseDrive>()
            .having((s) => s.drives, 'drives', [website, photos]),
      );
    });

    test('asks for a drive first when there is none', () {
      final step = decide(
        showingDrivesList: true,
        drivesState: drives(const []),
      );

      expect(step, isA<UploadNeedsDrive>());
    });

    /// Nobody can add to a drive somebody else owns.
    test('does not count drives shared with the reader', () {
      final step = decide(
        showingDrivesList: true,
        drivesState: drives(const [], shared: [website]),
      );

      expect(step, isA<UploadNeedsDrive>());
    });

    test('offers nothing before the drives are known', () {
      final step = decide(
        showingDrivesList: true,
        drivesState: DrivesLoadInProgress(),
      );

      expect(step, isA<UploadNotYet>());
    });
  });
}
