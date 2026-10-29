import 'dart:typed_data';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHideBloc extends MockBloc<HideEvent, HideState>
    implements HideBloc {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

class _MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

UploadReviewSummary _summary({bool isFree = false, bool isCovered = false}) =>
    UploadReviewSummary(
      method: UploadMethod.turbo,
      isFree: isFree,
      priceUnavailable: false,
      isCovered: isCovered,
      overFreeAllowance: !isFree,
      offersPaymentChoice: false,
      usesLegacySelector: false,
      creditsCost: BigInt.from(40000000),
      creditsBalance: isCovered ? BigInt.from(10).pow(12) : BigInt.zero,
      usdCost: 0.0002,
      arCost: BigInt.zero,
    );

ConfirmingHideState _confirming(UploadReviewSummary summary,
        {bool refused = false}) =>
    ConfirmingHideState(
      uploadMethod: UploadMethod.turbo,
      hideAction: HideAction.hideFile,
      dataItems: const [],
      hideEntitySettings: HideEntitySettings<String>(
        isHidden: true,
        entry: 'notes.txt',
        entity: FileEntity(),
        dataItem: DataItem.withBlobData(data: Uint8List(0)),
      ),
      cost: MetadataWriteCost(summary),
      refused: refused,
    );

/// Hiding stays instant while it is free. When it isn't, the dialog shows the
/// change review instead of paying on its own.
void main() {
  late _MockHideBloc hideBloc;
  late _MockDriveDetailCubit driveDetail;

  setUpAll(() => registerFallbackValue(const ConfirmUploadEvent()));

  Future<void> pump(WidgetTester tester, List<HideState> states) async {
    hideBloc = _MockHideBloc();
    whenListen(
      hideBloc,
      Stream.fromIterable(states),
      initialState:
          const PreparingAndSigningHideState(hideAction: HideAction.hideFile),
    );
    final globalHide = _MockGlobalHideBloc();
    when(() => globalHide.state)
        .thenReturn(const GlobalHideInitial(userHasHiddenDrive: false));
    driveDetail = _MockDriveDetailCubit();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HideBloc>.value(value: hideBloc),
          BlocProvider<GlobalHideBloc>.value(value: globalHide),
        ],
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: HideDialog(driveDetailCubit: driveDetail),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('free: confirmed straight away, with no review', (tester) async {
    await pump(tester, [_confirming(_summary(isFree: true, isCovered: true))]);

    verify(() => hideBloc.add(const ConfirmUploadEvent())).called(1);
    expect(find.text('Hide file'), findsNothing);
  });

  testWidgets('not free: the review, with its price, and nothing confirmed',
      (tester) async {
    await pump(tester, [_confirming(_summary(isCovered: true))]);

    verifyNever(() => hideBloc.add(const ConfirmUploadEvent()));
    expect(find.text('Hide file'), findsOneWidget);
    expect(find.textContaining('< \$0.01'), findsOneWidget);

    await tester.tap(find.text('Hide'));
    verify(() => hideBloc.add(const ConfirmUploadEvent())).called(1);
  });

  testWidgets('refused by Turbo: Add credits, not another try', (tester) async {
    await pump(tester, [_confirming(_summary(), refused: true)]);

    verifyNever(() => hideBloc.add(const ConfirmUploadEvent()));
    expect(find.text('Add credits'), findsOneWidget);
    expect(
        find.textContaining('This change is over your free upload allowance.'),
        findsOneWidget);

    await tester.tap(find.text('Add credits'));
    await tester.pumpAndSettle();
    expect(find.text('Add Turbo Credits'), findsOneWidget);
  });
}
