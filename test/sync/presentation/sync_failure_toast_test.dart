import 'dart:async';

import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/sync_failure_toast.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

/// Where there is no sync indicator, as in a publication, a failed sync is
/// reported as a toast; where there is one, it is reported there, once.
void main() {
  late MockSyncBloc syncCubit;
  late StreamController<SyncState> states;

  setUp(() {
    syncCubit = MockSyncBloc();
    states = StreamController<SyncState>.broadcast();
    whenListen(syncCubit, states.stream, initialState: SyncIdle());
    when(() => syncCubit.retryFailure()).thenAnswer((_) async {});
  });

  tearDown(() => states.close());

  Future<void> pump(WidgetTester tester, {required bool enabled}) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => BlocProvider<SyncCubit>.value(
          value: syncCubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SyncFailureToastListener(
                enabled: enabled,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('with no indicator on screen, a failure is a toast',
      (tester) async {
    await pump(tester, enabled: true);

    states.add(SyncFailure(kind: SyncFailureKind.sync));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Sync stopped with an error'), findsOneWidget);

    // Try again repeats what failed, not a sync of every drive.
    await tester.tap(find.text('Try again'));
    await tester.pump();
    verify(() => syncCubit.retryFailure()).called(1);

    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a drive list that could not be read says so', (tester) async {
    await pump(tester, enabled: true);

    states.add(SyncFailure());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Drives could not be loaded'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('with the indicator on screen, it stays quiet', (tester) async {
    await pump(tester, enabled: false);

    states.add(SyncFailure(kind: SyncFailureKind.sync));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Sync stopped with an error'), findsNothing);
  });
}
