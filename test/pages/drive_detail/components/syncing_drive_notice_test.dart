import 'dart:async';

import 'package:ardrive/pages/drive_detail/components/syncing_drive_notice.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_utils/mocks.dart';

void main() {
  late MockSyncBloc syncCubit;
  late StreamController<SyncState> stateController;

  setUp(() {
    syncCubit = MockSyncBloc();
    stateController = StreamController<SyncState>.broadcast();
    whenListen(syncCubit, stateController.stream, initialState: SyncIdle());
  });

  tearDown(() async => stateController.close());

  Widget wrap({ArDriveThemeData? theme}) => ArDriveTheme(
        themeData: theme ?? lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: BlocProvider<SyncCubit>.value(
              value: syncCubit,
              child: const SyncingDriveNotice(driveId: 'drive-on-screen'),
            ),
          ),
        ),
      );

  const line =
      'Still reading this drive, so more items may appear. Selecting several is paused until it finishes.';

  testWidgets('a running sync says why several items cannot be selected',
      (tester) async {
    // The lock is old; the silence is what a background sync made reachable.
    // With the app usable for the whole login sync, ctrl/cmd-click and ctrl-A
    // were hard no-ops with nothing disabled and no explanation, which reads
    // as the app being broken rather than busy.
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text(line), findsNothing,
        reason: 'precondition: nothing is said when nothing is locked');

    stateController.add(SyncInProgress(trigger: SyncTrigger.background));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text(line), findsOneWidget);
  });

  testWidgets('it says nothing once the sync is over', (tester) async {
    await tester.pumpWidget(wrap());
    stateController.add(SyncInProgress(trigger: SyncTrigger.background));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text(line), findsOneWidget);

    stateController.add(SyncComplete(
      entitiesSynced: 0,
      completedAt: DateTime.now(),
      sequence: 1,
    ));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text(line), findsNothing);
    // And it leaves nothing behind in the layout it was sharing.
    expect(tester.getSize(find.byType(SyncingDriveNotice)), Size.zero);
  });

  test('the notice and the lock read the same condition', () {
    bool locks(SyncState state, {String? syncingDriveId}) =>
        SyncingDriveNotice.locksMultiSelect(
          state,
          syncingDriveId: syncingDriveId,
          driveId: 'drive-on-screen',
        );

    // The data table is locked with this exact predicate. Deriving the two
    // separately is how the notice goes quiet while the lock stays on.
    expect(
      locks(SyncInProgress(trigger: SyncTrigger.background)),
      isTrue,
      reason: 'an all-drives sync writes this drive too',
    );
    expect(
      locks(SyncInProgress(trigger: SyncTrigger.userInitiated)),
      isTrue,
    );
    expect(locks(SyncIdle()), isFalse);
    expect(
      locks(SyncLoadingDrives()),
      isFalse,
      reason: 'loading the drives list rewrites no rows in the open folder',
    );
  });

  /// The limitation this removes: syncing one drive used to disable selection
  /// in every other one, including drives that sync was never going to write.
  test('only a sync that could write this drive holds its selection', () {
    bool locks(String? syncingDriveId) => SyncingDriveNotice.locksMultiSelect(
          SyncInProgress(trigger: SyncTrigger.userInitiated),
          syncingDriveId: syncingDriveId,
          driveId: 'drive-on-screen',
        );

    expect(
      locks('a-different-drive'),
      isFalse,
      reason: 'nothing is rewriting the rows the reader is selecting',
    );
    expect(locks('drive-on-screen'), isTrue);
    expect(
      locks(null),
      isTrue,
      reason: 'an all-drives sync really is writing every drive',
    );
  });

  testWidgets('it is drawn in the theme it lands in', (tester) async {
    Future<Color> textColourUnder(ArDriveThemeData theme) async {
      await tester.pumpWidget(wrap(theme: theme));
      stateController.add(SyncInProgress(trigger: SyncTrigger.background));
      await tester.pump(const Duration(milliseconds: 10));

      final text = tester.widget<Text>(find.text(line));
      await tester.pumpWidget(const SizedBox());

      return text.style!.color!;
    }

    final light = await textColourUnder(lightTheme());
    final dark = await textColourUnder(
      ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
    );

    expect(light, lightTheme().colorTokens.textLow);
    expect(dark, ArDriveColorTokens.darkMode().textLow);
    expect(light, isNot(dark));
  });

  /// The fact this notice exists for, kept honest by name.
  ///
  /// A reader can now open a drive while it is being walked - which is the
  /// point - and a list that is four files long during a sync is four *so
  /// far*. Nothing else on the screen says so: the ring in the top bar reports
  /// that a sync is running, not that this list is short because of it.
  testWidgets('says the list is still filling, not only that selection is off',
      (tester) async {
    await tester.pumpWidget(wrap());
    stateController.add(SyncInProgress(trigger: SyncTrigger.background));
    await tester.pump();

    final text = tester.widget<Text>(find.byType(Text)).data!;

    expect(
      text.toLowerCase(),
      contains('more items may appear'),
      reason: 'a reader who cannot tell four from four-so-far will read a '
          'half-walked drive as a drive that lost files',
    );
  });
}
