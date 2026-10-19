import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/search/search_result_navigator.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

/// The explorer showing [currentDrive]. Only the drive matters here.
class _Showing extends Fake implements DriveDetailLoadSuccess {
  _Showing(this.currentDrive);

  @override
  final Drive currentDrive;
}

/// Going to a search result from the explorer, where the page changes drive
/// underneath and opens the new drive's root on its own.
void main() {
  late MockDrivesCubit drivesCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late StreamController<DriveDetailState> explorer;

  Drive drive(String id) => Drive(
        id: id,
        rootFolderId: '$id-root',
        ownerAddress: 'me',
        name: id,
        privacy: 'public',
        isHidden: false,
        dateCreated: DateTime(2026),
        lastUpdated: DateTime(2026),
      );

  final work = drive('work');
  final home = drive('home');

  final favorites = SearchResult<FolderEntry>(
    result: FolderEntry(
      id: 'favorites',
      driveId: 'work',
      name: 'Favorites',
      parentFolderId: 'work-root',
      path: '',
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
      isGhost: false,
      isHidden: false,
    ),
    drive: work,
  );

  final report = SearchResult<FileEntry>(
    result: FileEntry(
      id: 'report',
      driveId: 'work',
      name: 'report.pdf',
      parentFolderId: 'favorites',
      path: '',
      size: 1,
      lastModifiedDate: DateTime(2026),
      dataTxId: 'tx',
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
      isHidden: false,
    ),
    drive: work,
  );

  void expectNoFolderOpened() => verifyNever(() => driveDetailCubit.openFolder(
        otherDriveId: any(named: 'otherDriveId'),
        folderId: any(named: 'folderId'),
        selectedItemId: any(named: 'selectedItemId'),
      ));

  setUp(() {
    drivesCubit = MockDrivesCubit();
    driveDetailCubit = MockDriveDetailCubit();
    explorer = StreamController<DriveDetailState>.broadcast();

    when(() => driveDetailCubit.openFolder(
          otherDriveId: any(named: 'otherDriveId'),
          folderId: any(named: 'folderId'),
          selectedItemId: any(named: 'selectedItemId'),
        )).thenAnswer((_) async {});
  });

  tearDown(() => explorer.close());

  SearchResultNavigator navigator() => SearchResultNavigator(
        drivesCubit: drivesCubit,
        driveDetailCubit: driveDetailCubit,
      );

  test('a folder in another drive opens once the explorer shows that drive',
      () async {
    whenListen(driveDetailCubit, explorer.stream, initialState: _Showing(home));

    final going = navigator().open(favorites);
    await pumpEventQueue();

    verify(() => drivesCubit.selectDrive('work')).called(1);
    // Asked for now, the page's own opening of the drive's root would
    // replace it.
    expectNoFolderOpened();

    explorer.add(DriveDetailLoadInProgress());
    explorer.add(_Showing(work));
    await going;

    verify(() => driveDetailCubit.openFolder(
          otherDriveId: 'work',
          folderId: 'favorites',
        )).called(1);
  });

  test('a folder in the drive on screen opens at once', () async {
    whenListen(driveDetailCubit, explorer.stream, initialState: _Showing(work));

    await navigator().open(favorites);

    verify(() => driveDetailCubit.openFolder(
          otherDriveId: 'work',
          folderId: 'favorites',
        )).called(1);
  });

  test('a file opens its folder with it picked out, once its drive shows',
      () async {
    whenListen(driveDetailCubit, explorer.stream, initialState: _Showing(home));

    final going = navigator().open(report);
    await pumpEventQueue();
    expectNoFolderOpened();

    explorer.add(_Showing(work));
    await going;

    verify(() => driveDetailCubit.openFolder(
          otherDriveId: 'work',
          folderId: 'favorites',
          selectedItemId: 'report',
        )).called(1);
  });
}
