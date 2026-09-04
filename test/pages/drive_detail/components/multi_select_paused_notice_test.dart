import 'dart:async';

import 'package:ardrive/pages/drive_detail/components/multi_select_paused_notice.dart';
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
              child: const MultiSelectPausedNotice(),
            ),
          ),
        ),
      );

  const line = 'Selecting several items is paused while syncing';

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
    expect(tester.getSize(find.byType(MultiSelectPausedNotice)), Size.zero);
  });

  test('the notice and the lock read the same condition', () {
    // The data table is locked with this exact predicate. Deriving the two
    // separately is how the notice goes quiet while the lock stays on.
    expect(
      MultiSelectPausedNotice.locksMultiSelect(
        SyncInProgress(trigger: SyncTrigger.background),
      ),
      isTrue,
    );
    expect(
      MultiSelectPausedNotice.locksMultiSelect(
        SyncInProgress(trigger: SyncTrigger.userInitiated),
      ),
      isTrue,
    );
    expect(MultiSelectPausedNotice.locksMultiSelect(SyncIdle()), isFalse);
    expect(
      MultiSelectPausedNotice.locksMultiSelect(SyncLoadingDrives()),
      isFalse,
      reason: 'loading the drives list rewrites no rows in the open folder',
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
}
