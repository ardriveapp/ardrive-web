import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPublishCubit extends MockCubit<PublishState>
    implements PublishCubit {}

const _summary = PublicationSummary(
  fileCount: 3,
  folderCount: 1,
  totalSize: 1024,
  hiddenItems: 0,
  inHiddenFolders: 0,
  inGhostFolders: 0,
  pendingFiles: 0,
  failedFiles: 0,
);

final _freeCost = DriveStatePublishCost(
  costEstimateAr: UploadCostEstimate.zero(),
  costEstimateTurbo: UploadCostEstimate.zero(),
  isTurboUploadPossible: true,
  hasNoTurboBalance: false,
  arBalance: '0',
  turboCredits: '0',
  sufficientArBalance: true,
  sufficientTurboBalance: true,
  freeStatus: FreeUploadStatus.free,
);

void main() {
  late _MockPublishCubit cubit;

  setUp(() {
    cubit = _MockPublishCubit();
    when(() => cubit.scopeName).thenReturn('Archive');
    when(() => cubit.folder).thenReturn(null);
  });

  Widget app(Widget home) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: home),
        ),
      );

  Future<void> open(WidgetTester tester, PublishState state) async {
    when(() => cubit.state).thenReturn(state);
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlocProvider<PublishCubit>.value(
            value: cubit,
            child: const PublishDialog(),
          ),
        ),
        child: const Text('Publish to web'),
      ),
    )));
    await tester.tap(find.text('Publish to web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the review leaves the snapshot to the total', (tester) async {
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        cost: _freeCost,
      ),
    );

    expect(find.text('Review and publish'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget, reason: 'the rest stays');
    expect(find.text('Snapshot'), findsNothing);
    expect(find.textContaining('snapshot'), findsNothing);
  });

  group('while publishing', () {
    final publishing = PublishState(
      stage: PublishStage.publishing,
      summary: _summary,
      title: 'Archive',
      cost: _freeCost,
    );

    testWidgets('Close hides the dialog; back does not', (tester) async {
      await open(tester, publishing);
      expect(find.byType(PublishDialog), findsOneWidget);
      expect(find.text('Keep this tab open until it\'s done.'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PublishDialog), findsOneWidget,
          reason: 'back never hides a publish in progress');

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(PublishDialog), findsNothing);
    });
  });

  group('the notice after a closed publish settles', () {
    Future<(ScaffoldMessengerState, AppLocalizations)> host(
        WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(app(Builder(builder: (c) {
        context = c;
        return const SizedBox.shrink();
      })));
      return (
        ScaffoldMessenger.of(context),
        AppLocalizations.of(context)!,
      );
    }

    testWidgets('says the page is published, with Open', (tester) async {
      final (messenger, strings) = await host(tester);
      showPublishSettledNotice(
          messenger, strings, 'https://ardrive.net/MANIFEST/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text('Your page is published'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Open'), findsOneWidget);
    });

    testWidgets('says how to try again when it stopped', (tester) async {
      final (messenger, strings) = await host(tester);
      showPublishSettledNotice(messenger, strings, null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(
        find.text('Publishing stopped. Open Publish to web to try again.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBarAction), findsNothing);
    });
  });
}
