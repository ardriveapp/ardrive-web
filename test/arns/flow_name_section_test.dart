import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

class _MockNameCubit extends MockCubit<ArNSNameDialogState>
    implements ArNSFlowNameCubit {}

/// The name step inside a flow such as an upload: one row like the options
/// under it, not a boxed card.
void main() {
  Future<void> pump(WidgetTester tester, ArNSDialogStage stage) async {
    final names = _MockNameCubit();
    whenListen(
      names,
      const Stream<ArNSNameDialogState>.empty(),
      initialState: ArNSNameDialogState(
        mode: ArNSNameDialogMode.nameItem,
        stage: stage,
      ),
    );
    when(() => names.ready).thenReturn(true);
    when(() => names.hasWork).thenReturn(false);
    when(() => names.repointing).thenReturn(null);
    final wallet = _MockWalletCubit();
    whenListen(wallet, const Stream<ArNSWalletState>.empty(),
        initialState: const ArNSWalletState());

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: BlocProvider<ArNSWalletCubit>.value(
              value: wallet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [ArNSFlowNameSection(cubit: names)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('is one row, the same as the options row, in no box',
      (tester) async {
    await pump(tester, ArNSDialogStage.choose);

    expect(find.text('Give it a name like yours.ar.io'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.byType(ArDriveDisclosure), findsOneWidget);
    expect(tester.getSize(find.byType(ArNSFlowNameSection)).height,
        ArDriveDisclosure.rowHeight);
    final boxes = find.descendant(
      of: find.byType(ArNSFlowNameSection),
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null),
    );
    expect(boxes, findsNothing);
  });

  testWidgets('with no names, offers Get a name on the row itself',
      (tester) async {
    await pump(tester, ArNSDialogStage.noNames);

    final row = tester.getRect(find.byType(ArDriveDisclosure));
    final link = find.byType(ArDriveLink);
    expect(link, findsOneWidget);
    expect(tester.widget<ArDriveLink>(link).text, 'Get a name');
    // On the row, at its end, rather than behind a chevron.
    expect(row.contains(tester.getCenter(link)), isTrue);
    expect(tester.getCenter(link).dx, greaterThan(row.center.dx));
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.text('No names yet'), findsNothing);
  });
}
