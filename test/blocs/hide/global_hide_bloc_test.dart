import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
    expect: () => [
      /// Show hidden files
      const ShowingHiddenItems(userHasHiddenDrive: true),

      /// Hide hidden files
      const HiddingItems(userHasHiddenDrive: true),
    ],
  );
}
