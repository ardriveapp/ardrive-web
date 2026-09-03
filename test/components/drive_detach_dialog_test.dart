import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSyncCubit extends MockBloc<dynamic, SyncState>
    implements SyncCubit {}

class _MockDrivesCubit extends MockBloc<dynamic, DrivesState>
    implements DrivesCubit {}

/// What a reader is told before detaching a drive somebody else owns.
///
/// Every path here is gated on `!isOwner`, so this is always a shared drive -
/// and a shared drive does not come back on its own. An owned drive is
/// rediscovered by the next drive-list refresh; a shared one was never
/// discovered at all, only linked to. The dialog used to ask "are you sure?"
/// and leave the reader to find that out afterwards.
void main() {
  late _MockSyncCubit syncCubit;
  late _MockDrivesCubit drivesCubit;

  setUp(() {
    syncCubit = _MockSyncCubit();
    drivesCubit = _MockDrivesCubit();

    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: DrivesLoadInProgress());
  });

  Future<void> openDialog(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      // Providers above the MaterialApp, as they are in the real app: a
      // dialog is pushed as its own route, so anything scoped inside `home`
      // is not an ancestor of it.
      MultiProvider(
        providers: [
          // `showArDriveDialog` reads it to hold sync off while a modal is up;
          // nothing this test asserts depends on what it says.
          ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker(),
          ),
          BlocProvider<SyncCubit>.value(value: syncCubit),
          BlocProvider<DrivesCubit>.value(value: drivesCubit),
        ],
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', '')],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDetachDriveDialog(
                      context: context,
                      driveID: 'drive-a',
                      driveName: 'Photos',
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the drive and says what getting it back costs',
      (tester) async {
    await openDialog(tester);

    expect(find.textContaining('Photos'), findsOneWidget);
    expect(
      find.textContaining('share link'),
      findsOneWidget,
      reason: 'the one thing that makes this different from detaching a drive '
          'you own, and the one thing a reader can act on beforehand',
    );
  });

  testWidgets('and says nothing about a sync when none is running',
      (tester) async {
    await openDialog(tester);

    expect(find.textContaining('will be stopped first'), findsNothing);
  });

  testWidgets('but does when one is', (tester) async {
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
    when(() => syncCubit.syncingDriveId).thenReturn('drive-a');

    await openDialog(tester);

    expect(
      find.textContaining('will be stopped first'),
      findsOneWidget,
      reason: 'detaching cancels the sync and waits for it - a reader watching '
          'a ring turn should not have to guess whether the two race',
    );
  });

  testWidgets('fits a 320px phone without overflowing', (tester) async {
    await openDialog(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('share link'), findsOneWidget);
  });

  testWidgets('detaching asks the cubit to do it', (tester) async {
    when(() => drivesCubit.detachDrive(any())).thenAnswer((_) async {});

    await openDialog(tester);
    await tester.tap(find.text('DETACH'));
    await tester.pumpAndSettle();

    verify(() => drivesCubit.detachDrive('drive-a')).called(1);
  });
}
