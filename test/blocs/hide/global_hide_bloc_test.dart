import 'dart:async';

import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/models/models.dart' hide DriveDao;
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class MockDriveDao extends Mock implements DriveDao {}

void main() {
  late MockUserPreferencesRepository mockUserPreferencesRepository;
  late MockDriveDao mockDriveDao;

  setUp(() {
    mockUserPreferencesRepository = MockUserPreferencesRepository();
    mockDriveDao = MockDriveDao();
    when(() => mockUserPreferencesRepository.clear()).thenAnswer((_) async {});
    when(() => mockUserPreferencesRepository.load()).thenAnswer((_) async {
      return const UserPreferences(
        showHiddenFiles: false,
        userHasHiddenDrive: false,
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: '',
      );
    });

    when(() => mockUserPreferencesRepository.watch()).thenAnswer(
      (_) => const Stream.empty(),
    );
    when(() => mockDriveDao.userHasHiddenItems())
        .thenAnswer((_) async => false);
    when(() => mockDriveDao.watchUserHasHiddenItems())
        .thenAnswer((_) => const Stream.empty());
  });

  blocTest<GlobalHideBloc, GlobalHideState>(
    'initial state is correct',
    setUp: () {
      when(() => mockUserPreferencesRepository.saveShowHiddenFiles(false))
          .thenAnswer((_) async {});
    },
    build: () => GlobalHideBloc(
      userPreferencesRepository: mockUserPreferencesRepository,
      driveDao: mockDriveDao,
    ),
    verify: (bloc) {
      expect(bloc.state, const GlobalHideInitial(userHasHiddenDrive: false));
    },
  );

  blocTest<GlobalHideBloc, GlobalHideState>(
    'ShowItems event emits ShowingHiddenItems state and saves preference',
    build: () {
      when(() => mockUserPreferencesRepository.saveShowHiddenFiles(true))
          .thenAnswer((_) async {});
      return GlobalHideBloc(
        userPreferencesRepository: mockUserPreferencesRepository,
        driveDao: mockDriveDao,
      );
    },
    act: (bloc) => bloc.add(const ShowItems(userHasHiddenItems: true)),
    expect: () => [const ShowingHiddenItems(userHasHiddenDrive: true)],
    verify: (_) {
      verify(() => mockUserPreferencesRepository.saveShowHiddenFiles(true))
          .called(1);
    },
  );

  blocTest<GlobalHideBloc, GlobalHideState>(
    'HideItems event emits HiddingItems state and saves preference',
    build: () {
      when(() => mockUserPreferencesRepository.saveShowHiddenFiles(false))
          .thenAnswer((_) async {});
      return GlobalHideBloc(
        userPreferencesRepository: mockUserPreferencesRepository,
        driveDao: mockDriveDao,
      );
    },
    act: (bloc) => bloc.add(const HideItems(userHasHiddenItems: false)),
    expect: () => [const HiddingItems(userHasHiddenDrive: false)],
    verify: (_) {
      verify(() => mockUserPreferencesRepository.saveShowHiddenFiles(false))
          .called(1);
    },
  );

  blocTest<GlobalHideBloc, GlobalHideState>(
    'RefreshOptions event emits updated state with userHasHiddenDrive',
    build: () {
      when(() => mockDriveDao.userHasHiddenItems())
          .thenAnswer((_) async => true);
      return GlobalHideBloc(
        userPreferencesRepository: mockUserPreferencesRepository,
        driveDao: mockDriveDao,
      );
    },
    act: (bloc) => bloc.add(const RefreshOptions(userHasHiddenItems: true)),
    expect: () => [const GlobalHideInitial(userHasHiddenDrive: true)],
    verify: (_) {
      verify(() => mockDriveDao.userHasHiddenItems()).called(1);
    },
  );

  blocTest<GlobalHideBloc, GlobalHideState>(
    'UserPreferencesRepository updates trigger events',
    build: () {
      // This test case verifies that the GlobalHideBloc correctly responds to
      // changes in the UserPreferencesRepository. It simulates two scenarios:
      //
      // 1. When showHiddenFiles is set to true:
      //    - The bloc should emit a ShowingHiddenItems state
      //    - The userHasHiddenDrive property should be true
      //
      // 2. When showHiddenFiles is set to false:
      //    - The bloc should emit a HiddingItems state
      //    - The userHasHiddenDrive property should remain true
      when(() => mockUserPreferencesRepository.watch()).thenAnswer(
        (_) => Stream.fromIterable([
          /// Show hidden files
          const UserPreferences(
              showHiddenFiles: true,
              userHasHiddenDrive: true,
              currentTheme: ArDriveThemes.light,
              lastSelectedDriveId: ''),

          /// Hide hidden files
          const UserPreferences(
              showHiddenFiles: false,
              userHasHiddenDrive: true,
              currentTheme: ArDriveThemes.light,
              lastSelectedDriveId: ''),
        ]),
      );

      when(() => mockDriveDao.userHasHiddenItems())
          .thenAnswer((_) async => true);

      when(() => mockUserPreferencesRepository.saveShowHiddenFiles(any()))
          .thenAnswer((_) async {});

      return GlobalHideBloc(
        userPreferencesRepository: mockUserPreferencesRepository,
        driveDao: mockDriveDao,
      );
    },
    // Whether anything is hidden is the database's to say, not the stored
    // flag's (#25): nothing hidden has been reported here, so it is false.
    expect: () => [
      /// Show hidden files
      const ShowingHiddenItems(userHasHiddenDrive: false),

      /// Hide hidden files
      const HiddingItems(userHasHiddenDrive: false),
    ],
  );

  // #25: the eye followed a stored flag that lagged a sync and counted hidden
  // drives alone, so it showed and hid at the wrong times.
  blocTest<GlobalHideBloc, GlobalHideState>(
    'whether anything is hidden follows the database',
    build: () {
      when(() => mockDriveDao.watchUserHasHiddenItems())
          .thenAnswer((_) => Stream.fromIterable([true, false]));
      return GlobalHideBloc(
        userPreferencesRepository: mockUserPreferencesRepository,
        driveDao: mockDriveDao,
      );
    },
    expect: () => [
      const GlobalHideInitial(userHasHiddenDrive: true),
      const GlobalHideInitial(userHasHiddenDrive: false),
    ],
  );

  blocTest<GlobalHideBloc, GlobalHideState>(
    'and the preferences do not overwrite it with their stored flag',
    build: () {
      final db = StreamController<bool>();
      final prefs = StreamController<UserPreferences>();
      when(() => mockDriveDao.watchUserHasHiddenItems())
          .thenAnswer((_) => db.stream);
      when(() => mockUserPreferencesRepository.watch())
          .thenAnswer((_) => prefs.stream);
      final bloc = GlobalHideBloc(
        userPreferencesRepository: mockUserPreferencesRepository,
        driveDao: mockDriveDao,
      );
      db.add(true);
      Future.delayed(const Duration(milliseconds: 10), () {
        prefs.add(const UserPreferences(
          showHiddenFiles: true,
          userHasHiddenDrive: false,
          currentTheme: ArDriveThemes.light,
          lastSelectedDriveId: '',
        ));
      });
      return bloc;
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const GlobalHideInitial(userHasHiddenDrive: true),
      const ShowingHiddenItems(userHasHiddenDrive: true),
    ],
  );

  test('DriveDao watches hidden drives, folders and files', () async {
    final db = getTestDb();
    addTearDown(db.close);
    final seen = <bool>[];
    final sub = db.driveDao.watchUserHasHiddenItems().listen(seen.add);
    await Future.delayed(Duration.zero);
    await db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
          id: 'f',
          driveId: 'd',
          parentFolderId: 'r',
          name: 'f',
          dataTxId: 'tx',
          size: 1,
          lastModifiedDate: DateTime(2024),
          path: '',
          isHidden: const Value(true),
        ));
    await Future.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(seen, [false, true]);
  });
}
