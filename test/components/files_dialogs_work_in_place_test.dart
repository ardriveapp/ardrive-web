import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/folder_create_form.dart';
import 'package:ardrive/components/fs_entry_move_form.dart';
import 'package:ardrive/components/fs_entry_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

class _MockRename extends MockCubit<FsEntryRenameState>
    implements FsEntryRenameCubit {}

class _MockCreate extends MockCubit<FolderCreateState>
    implements FolderCreateCubit {}

class _MockMove extends MockBloc<FsEntryMoveEvent, FsEntryMoveState>
    implements FsEntryMoveBloc {}

class _MockGlobalHide extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

class _MockProfile extends MockCubit<ProfileState> implements ProfileCubit {}

class _MockTurbo extends Mock implements TurboUploadService {}

class _FakeMoveEvent extends Fake implements FsEntryMoveEvent {}

class _MockGhost extends MockCubit<GhostFixerState>
    implements GhostFixerCubit {}

/// Rename, create folder, recreate folder: each does its work in its own
/// dialog. No progress dialog, error dialog or conflict dialog opens on top;
/// the primary is busy, Cancel is held, and a failure or a taken name is said
/// in the dialog, which stays open.
void main() {
  setUpAll(() => registerFallbackValue(_FakeMoveEvent()));

  /// What the create folder step reads from the app to make its own cubit.
  Widget withServices(Widget child) => MultiProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfile()),
          Provider<ArweaveService>.value(value: MockArweaveService()),
          Provider<TurboUploadService>.value(value: _MockTurbo()),
          Provider<DriveDao>.value(value: MockDriveDao()),
        ],
        child: child,
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: withServices(child)),
        ),
      ),
    );
    await tester.pump();
  }

  // By its text property: a busy button shows a spinner in place of it.
  ArDriveButtonNew button(WidgetTester tester, String text) =>
      tester.widget<ArDriveButtonNew>(find
          .byWidgetPredicate((w) => w is ArDriveButtonNew && w.text == text));

  void expectOneDialog() {
    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.byType(ProgressDialog), findsNothing);
  }

  group('rename', () {
    late _MockRename cubit;
    late StreamController<FsEntryRenameState> states;

    setUp(() {
      cubit = _MockRename();
      states = StreamController<FsEntryRenameState>.broadcast();
      whenListen(
        cubit,
        states.stream,
        initialState: const FsEntryRenameInitialized(isRenamingFolder: false),
      );
      when(() => cubit.submit(
            newName: any(named: 'newName'),
            updateExtension: any(named: 'updateExtension'),
          )).thenAnswer((_) async {});
      when(() => cubit.reset()).thenAnswer((_) async {});
    });

    tearDown(() => states.close());

    Future<void> open(WidgetTester tester) async {
      await pump(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<FsEntryRenameCubit>.value(value: cubit),
            BlocProvider<DriveDetailCubit>.value(value: MockDriveDetailCubit()),
          ],
          child: const FsEntryRenameForm(entryName: 'photo.png'),
        ),
      );
      await tester.enterText(find.byType(TextField), 'holiday.png');
      await tester.pump();
    }

    testWidgets('the name field has its label', (tester) async {
      await open(tester);

      expect(find.text('Name'), findsOneWidget);
      expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);
    });

    testWidgets('while it renames the primary is busy and Cancel is held',
        (tester) async {
      await open(tester);

      states.add(const FileEntryRenameInProgress());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.byType(ArDriveSpinner), findsOneWidget);
      expect(button(tester, 'Rename').isDisabled, isTrue);
      expect(button(tester, 'Cancel').isDisabled, isTrue);
      expect(
          tester
              .widget<ArDriveTextFieldNew>(find.byType(ArDriveTextFieldNew))
              .isEnabled,
          isFalse);
    });

    testWidgets('a failure is a notice in the dialog, with Try again',
        (tester) async {
      await open(tester);

      states.add(const FileEntryRenameFailure());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.byType(ArDriveNotice), findsOneWidget);
      expect(find.text('Could not rename'), findsOneWidget);
      // The name is still there to fix or send again.
      expect(find.text('holiday.png'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      verify(() => cubit.submit(
            newName: 'holiday.png',
            updateExtension: false,
          )).called(1);
    });

    testWidgets('a taken name is said in the dialog and goes on editing',
        (tester) async {
      await open(tester);

      states.add(
          const EntityAlreadyExists('holiday.png', isRenamingFolder: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.byType(ArDriveNotice), findsOneWidget);
      expect(
          find.textContaining('holiday.png is already here'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'holiday2.png');
      await tester.pump();
      expect(find.byType(ArDriveNotice), findsNothing);
    });

    testWidgets('a changed extension is confirmed in the same dialog',
        (tester) async {
      await open(tester);

      states.add(const UpdatingEntityExtension(
        entityName: 'holiday.jpg',
        newExtension: 'jpg',
        previousExtension: 'png',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.text('Change the file extension?'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(button(tester, 'Back').variant, ButtonVariant.secondary);

      await tester.tap(find.text('Back'));
      verify(() => cubit.reset()).called(1);
    });

    testWidgets('confirming the extension renames with it', (tester) async {
      await open(tester);

      states.add(const UpdatingEntityExtension(
        entityName: 'holiday.jpg',
        newExtension: 'jpg',
        previousExtension: 'png',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Rename'), warnIfMissed: false);
      verify(() => cubit.submit(
            newName: 'holiday.png',
            updateExtension: true,
          )).called(1);
    });
  });

  group('rename extension step', () {
    testWidgets('Rename goes busy at once, so a second press sends nothing',
        (tester) async {
      final cubit = _MockRename();
      final states = StreamController<FsEntryRenameState>.broadcast();
      addTearDown(states.close);
      whenListen(
        cubit,
        states.stream,
        initialState: const FsEntryRenameInitialized(isRenamingFolder: false),
      );
      when(() => cubit.submit(
            newName: any(named: 'newName'),
            updateExtension: any(named: 'updateExtension'),
          )).thenAnswer((_) async {});
      await pump(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<FsEntryRenameCubit>.value(value: cubit),
            BlocProvider<DriveDetailCubit>.value(value: MockDriveDetailCubit()),
          ],
          child: const FsEntryRenameForm(entryName: 'photo.png'),
        ),
      );
      await tester.enterText(find.byType(TextField), 'holiday.jpg');
      await tester.pump();
      states.add(const UpdatingEntityExtension(
        entityName: 'holiday.jpg',
        newExtension: 'jpg',
        previousExtension: 'png',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Rename'));
      await tester.pump();
      expect(find.byType(ArDriveSpinner), findsOneWidget);
      await tester.tap(find.byType(ArDriveButtonNew).last, warnIfMissed: false);
      await tester.pump();

      verify(() => cubit.submit(
            newName: 'holiday.jpg',
            updateExtension: true,
          )).called(1);
    });
  });

  group('create folder', () {
    late _MockCreate cubit;
    late StreamController<FolderCreateState> states;

    setUp(() {
      cubit = _MockCreate();
      states = StreamController<FolderCreateState>.broadcast();
      whenListen(cubit, states.stream, initialState: FolderCreateInitial());
      when(() => cubit.submit(folderName: any(named: 'folderName')))
          .thenAnswer((_) async {});
    });

    tearDown(() => states.close());

    Future<void> open(WidgetTester tester, {VoidCallback? onClose}) async {
      await pump(
        tester,
        BlocProvider<FolderCreateCubit>.value(
          value: cubit,
          child: FolderCreateForm(onClose: onClose),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Receipts');
      await tester.pump();
    }

    testWidgets('has a labelled field and a Cancel that is not red',
        (tester) async {
      await open(tester);

      expect(find.text('Name'), findsOneWidget);
      expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);
      expect(button(tester, 'Create folder').isDisabled, isFalse);
    });

    testWidgets('while it works the primary is busy and Cancel is held',
        (tester) async {
      await open(tester);

      states.add(FolderCreateInProgress());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(button(tester, 'Create folder').isDisabled, isTrue);
      expect(button(tester, 'Cancel').isDisabled, isTrue);
    });

    testWidgets('a taken name is a notice in the dialog', (tester) async {
      await open(tester);

      states.add(FolderCreateNameAlreadyExists(folderName: 'Receipts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.textContaining('Receipts is already here'), findsOneWidget);
    });

    testWidgets('a failure is a notice with Try again', (tester) async {
      await open(tester);

      states.add(FolderCreateFailure());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.text('Could not create the folder'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      verify(() => cubit.submit(folderName: 'Receipts')).called(1);
    });

    testWidgets('inside a picker, success and Cancel hand back to it',
        (tester) async {
      var closed = 0;
      await open(tester, onClose: () => closed++);

      states.add(FolderCreateSuccess());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(closed, 1);

      await tester.tap(find.text('Cancel'));
      expect(closed, 2);
    });
  });

  group('recreate folder', () {
    late _MockGhost cubit;
    late StreamController<GhostFixerState> states;

    FolderEntry folder(String id, {String? parent}) => FolderEntry(
          id: id,
          driveId: 'drive',
          name: id,
          parentFolderId: parent,
          path: '',
          dateCreated: DateTime(2024),
          lastUpdated: DateTime(2024),
          isGhost: false,
          isHidden: false,
        );

    late GhostFixerFolderLoadSuccess loaded;

    setUp(() {
      cubit = _MockGhost();
      states = StreamController<GhostFixerState>.broadcast();
      loaded = GhostFixerFolderLoadSuccess(
        viewingRootFolder: true,
        viewingFolder: FolderWithContents(
          folder: folder('root'),
          subfolders: [folder('Photos', parent: 'root')],
          files: const [],
        ),
        movingEntryId: 'ghost',
      );
      whenListen(cubit, states.stream, initialState: loaded);
      when(() => cubit.submit(any())).thenAnswer((_) async {});
    });

    tearDown(() => states.close());

    Future<void> open(WidgetTester tester) async {
      await pump(
        tester,
        BlocProvider<GhostFixerCubit>.value(
          value: cubit,
          child: GhostFixerForm(driveDetailCubit: MockDriveDetailCubit()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Recovered');
      await tester.pump();
    }

    testWidgets('the primary is named for the action, the field is labelled',
        (tester) async {
      await open(tester);

      expect(find.text('FIX'), findsNothing);
      expect(button(tester, 'Recreate folder').variant, ButtonVariant.primary);
      expect(find.text('Folder name'), findsOneWidget);
    });

    testWidgets('while it works the dialog stays as it was, busy',
        (tester) async {
      await open(tester);

      states.add(GhostFixerRepairInProgress());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      // The folders are still listed.
      expect(find.text('Photos'), findsOneWidget);
      expect(button(tester, 'Recreate folder').isDisabled, isTrue);
      expect(button(tester, 'Cancel').isDisabled, isTrue);
    });

    testWidgets('a taken name and a failure are said in the dialog',
        (tester) async {
      await open(tester);

      states
        ..add(GhostFixerNameConflict(name: 'Recovered'))
        ..add(loaded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expectOneDialog();
      expect(find.text('Name conflict'), findsOneWidget);

      states.add(GhostFixerFailure());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expectOneDialog();
      expect(find.text('Could not recreate the folder'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      verify(() => cubit.submit('Recovered')).called(1);
    });

    testWidgets('a failure stays when the folder list updates under it',
        (tester) async {
      await open(tester);

      states
        ..add(GhostFixerFailure())
        ..add(loaded);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Could not recreate the folder'), findsOneWidget);
    });

    testWidgets('Create folder opens in place of the list, not over it',
        (tester) async {
      await open(tester);

      await tester.tap(find.text('Create folder'));
      await tester.pump();

      expectOneDialog();
      expect(find.byType(FolderCreateForm), findsOneWidget);
      expect(find.text('Recreate folder'), findsNothing);
    });
  });

  group('move', () {
    setUpAll(() => registerFallbackValue(_FakeMoveEvent()));

    late _MockMove bloc;
    late StreamController<FsEntryMoveState> states;
    late FsEntryMoveLoadSuccess loaded;

    FolderEntry folder(String id, {String? parent}) => FolderEntry(
          id: id,
          driveId: 'drive',
          name: id,
          parentFolderId: parent,
          path: '',
          dateCreated: DateTime(2024),
          lastUpdated: DateTime(2024),
          isGhost: false,
          isHidden: false,
        );

    setUp(() {
      bloc = _MockMove();
      states = StreamController<FsEntryMoveState>.broadcast();
      loaded = FsEntryMoveLoadSuccess(
        viewingRootFolder: true,
        viewingFolder: FolderWithContents(
          folder: folder('root'),
          subfolders: [folder('Photos', parent: 'root')],
          files: const [],
        ),
        itemsToMove: const [],
      );
      whenListen(bloc, states.stream, initialState: loaded);
    });

    tearDown(() => states.close());

    Future<void> open(WidgetTester tester) async {
      final hide = _MockGlobalHide();
      whenListen(
        hide,
        const Stream<GlobalHideState>.empty(),
        initialState: const GlobalHideInitial(userHasHiddenDrive: false),
      );
      await pump(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<FsEntryMoveBloc>.value(value: bloc),
            BlocProvider<GlobalHideBloc>.value(value: hide),
            BlocProvider<DriveDetailCubit>.value(value: MockDriveDetailCubit()),
          ],
          child: const FsEntryMoveForm(),
        ),
      );
    }

    testWidgets('the picker is a standard dialog with standard actions',
        (tester) async {
      await open(tester);

      expectOneDialog();
      expect(find.text('Photos'), findsOneWidget);
      expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);
      expect(button(tester, 'Move here').variant, ButtonVariant.primary);
      // The close button is in the title row.
      expect(find.byType(ArDriveIcon), findsWidgets);
    });

    testWidgets('Move here is held in the folder the items are already in',
        (tester) async {
      final here = createMockFileDataTableItem(parentFolderId: 'root');
      final elsewhere = createMockFileDataTableItem(parentFolderId: 'Photos');
      whenListen(bloc, states.stream,
          initialState: FsEntryMoveLoadSuccess(
            viewingRootFolder: true,
            viewingFolder: loaded.viewingFolder,
            itemsToMove: [here],
          ));
      await open(tester);
      expect(button(tester, 'Move here').isDisabled, isTrue);

      states.add(FsEntryMoveLoadSuccess(
        viewingRootFolder: true,
        viewingFolder: loaded.viewingFolder,
        itemsToMove: [here, elsewhere],
      ));
      await tester.pump();
      expect(button(tester, 'Move here').isDisabled, isFalse);
    });

    testWidgets('while it moves the picker stays, busy', (tester) async {
      await open(tester);

      states.add(const FsEntryMoveLoadInProgress());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.text('Photos'), findsOneWidget);
      expect(button(tester, 'Move here').isDisabled, isTrue);
      expect(button(tester, 'Cancel').isDisabled, isTrue);
    });

    testWidgets('a failure is a notice in the picker, with Try again',
        (tester) async {
      await open(tester);

      states
        ..add(const FsEntryMoveLoadInProgress())
        ..add(const FsEntryMoveFailure());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.text('Could not move'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      verify(() => bloc.add(any(that: isA<FsEntryMoveSubmit>()))).called(1);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Create folder opens in place of the list, not over it',
        (tester) async {
      await open(tester);

      await tester.tap(find.text('Create folder'));
      await tester.pump();

      expectOneDialog();
      expect(find.byType(FolderCreateForm), findsOneWidget);
      expect(find.text('Move items'), findsNothing);
    });

    testWidgets(
        'a name conflict has Cancel and a primary that says what it does',
        (tester) async {
      await open(tester);

      final a = createMockFileDataTableItem(name: 'a.txt');
      final b = createMockFileDataTableItem(name: 'b.txt');
      states.add(FsEntryMoveNameConflict(
        conflictingItems: [a],
        folderInView: folder('root'),
        destinationName: 'Docs',
        allItems: [a, b],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expectOneDialog();
      expect(find.text('Name conflict'), findsOneWidget);
      expect(find.text('a.txt'), findsOneWidget);
      expect(button(tester, 'Cancel').variant, ButtonVariant.secondary);
      expect(find.text('Skip'), findsNothing);
      expect(button(tester, 'Skip and move the rest').variant,
          ButtonVariant.primary);
    });
  });

  group('a quick second press starts nothing', () {
    testWidgets('rename', (tester) async {
      final cubit = _MockRename();
      whenListen(
        cubit,
        const Stream<FsEntryRenameState>.empty(),
        initialState: const FsEntryRenameInitialized(isRenamingFolder: false),
      );
      // The cubit is still checking: it has not reported it is busy.
      final answer = Completer<void>();
      when(() => cubit.submit(
            newName: any(named: 'newName'),
            updateExtension: any(named: 'updateExtension'),
          )).thenAnswer((_) => answer.future);
      await pump(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<FsEntryRenameCubit>.value(value: cubit),
            BlocProvider<DriveDetailCubit>.value(value: MockDriveDetailCubit()),
          ],
          child: const FsEntryRenameForm(entryName: 'photo.png'),
        ),
      );
      await tester.enterText(find.byType(TextField), 'holiday.png');
      await tester.pump();

      final rename = find.byWidgetPredicate(
          (w) => w is ArDriveButtonNew && w.text == 'Rename');
      await tester.tap(rename);
      await tester.tap(rename, warnIfMissed: false);
      await tester.pump();

      verify(() => cubit.submit(
            newName: 'holiday.png',
            updateExtension: false,
          )).called(1);
      answer.complete();
      await tester.pump();
    });

    testWidgets('create folder', (tester) async {
      final cubit = _MockCreate();
      whenListen(cubit, const Stream<FolderCreateState>.empty(),
          initialState: FolderCreateInitial());
      final answer = Completer<void>();
      when(() => cubit.submit(folderName: any(named: 'folderName')))
          .thenAnswer((_) => answer.future);
      await pump(
        tester,
        BlocProvider<FolderCreateCubit>.value(
          value: cubit,
          child: const FolderCreateForm(),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Receipts');
      await tester.pump();

      final create = find.byWidgetPredicate(
          (w) => w is ArDriveButtonNew && w.text == 'Create folder');
      await tester.tap(create);
      await tester.tap(create, warnIfMissed: false);
      await tester.pump();

      verify(() => cubit.submit(folderName: 'Receipts')).called(1);
      answer.complete();
      await tester.pump();
    });

    testWidgets('move', (tester) async {
      final bloc = _MockMove();
      final loaded = FsEntryMoveLoadSuccess(
        viewingRootFolder: true,
        viewingFolder: FolderWithContents(
          folder: FolderEntry(
            id: 'root',
            driveId: 'drive',
            name: 'root',
            path: '',
            dateCreated: DateTime(2024),
            lastUpdated: DateTime(2024),
            isGhost: false,
            isHidden: false,
          ),
          subfolders: const [],
          files: const [],
        ),
        itemsToMove: const [],
      );
      whenListen(bloc, const Stream<FsEntryMoveState>.empty(),
          initialState: loaded);
      final hide = _MockGlobalHide();
      whenListen(
        hide,
        const Stream<GlobalHideState>.empty(),
        initialState: const GlobalHideInitial(userHasHiddenDrive: false),
      );
      await pump(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<FsEntryMoveBloc>.value(value: bloc),
            BlocProvider<GlobalHideBloc>.value(value: hide),
            BlocProvider<DriveDetailCubit>.value(value: MockDriveDetailCubit()),
          ],
          child: const FsEntryMoveForm(),
        ),
      );

      final move = find.byWidgetPredicate(
          (w) => w is ArDriveButtonNew && w.text == 'Move here');
      await tester.tap(move);
      await tester.tap(move, warnIfMissed: false);
      await tester.pump();

      verify(() => bloc.add(any(that: isA<FsEntryMoveSubmit>()))).called(1);
      // The flag lets go of a move that was turned back without a word.
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
