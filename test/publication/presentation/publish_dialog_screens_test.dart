@Tags(['measurement'])
library;

// Screenshots of the publish dialog's sync, included and progress steps, for
// review. Not an assertion: run with
// flutter test test/publication/presentation/publish_dialog_screens_test.dart --run-skipped --tags=measurement
// and find the PNGs in build/publish-shots.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart'
    show PublicationStep;
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPublishCubit extends MockCubit<PublishState>
    implements PublishCubit {}

class _MockNameCubit extends MockCubit<ArNSNameDialogState>
    implements ArNSFlowNameCubit {}

final _outDir = Directory('build/publish-shots');

Future<ByteData> _read(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadFonts() async {
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
  ]) {
    wavehaus.addFont(_read('$dir/$f'));
  }
  await wavehaus.load();
  await (FontLoader('packages/ardrive_ui/ArDriveIcons')
        ..addFont(_read('$dir/ArDriveIcons.ttf')))
      .load();
}

const _summary = PublicationSummary(
  fileCount: 302,
  folderCount: 42,
  totalSize: 4187593113,
  hiddenItems: 1,
  inHiddenFolders: 0,
  inGhostFolders: 0,
  pendingFiles: 0,
  failedFiles: 0,
);

final _cost = DriveStatePublishCost(
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
  setUpAll(_loadFonts);

  Future<void> capture(
    WidgetTester tester,
    String name,
    PublishState state, {
    required bool dark,
    bool canSync = false,
    ArNSCommitStep? nameStep,
  }) async {
    final cubit = _MockPublishCubit();
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.scopeName).thenReturn('Artists');
    when(() => cubit.folder).thenReturn(null);
    when(() => cubit.canSyncDrive).thenReturn(canSync);
    if (nameStep != null) {
      final names = _MockNameCubit();
      whenListen(
        names,
        const Stream<ArNSNameDialogState>.empty(),
        initialState: ArNSNameDialogState(
            mode: ArNSNameDialogMode.nameItem, step: nameStep),
      );
      when(() => cubit.names).thenReturn(names);
    }

    const size = Size(900, 640);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ArDriveApp(
          themeData: dark ? null : lightTheme(),
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ArDriveTheme.of(context).themeData.materialThemeData,
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor:
                    ArDriveTheme.of(context).themeData.colorTokens.containerL0,
                body: Center(
                  child: BlocProvider<PublishCubit>.value(
                    value: cubit,
                    child: const PublishDialog(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${_outDir.path}/$name-${dark ? 'dark' : 'light'}.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    testWidgets('blocked by sync, dark: $dark', (tester) async {
      await capture(
        tester,
        '1-blocked-sync',
        const PublishState(
          stage: PublishStage.blocked,
          blocked: PublishBlock.sync,
          blockedReason: 'No sync has finished yet, so there is nothing to '
              'confirm this drive is complete. Sync this drive, then try '
              'again.',
        ),
        dark: dark,
        canSync: true,
      );
    });

    testWidgets('syncing, dark: $dark', (tester) async {
      await capture(
          tester, '2-syncing', const PublishState(stage: PublishStage.syncing),
          dark: dark);
    });

    testWidgets('included, dark: $dark', (tester) async {
      await capture(
        tester,
        '3-included',
        const PublishState(stage: PublishStage.included, summary: _summary),
        dark: dark,
      );
    });

    testWidgets('updating the name, waiting on the wallet, dark: $dark',
        (tester) async {
      await capture(
        tester,
        '4-name-approve',
        PublishState(
          stage: PublishStage.publishing,
          summary: _summary,
          title: 'Playdead Music Archive',
          cost: _cost,
          isUpdate: true,
          step: PublicationStep.warmUp,
          naming: const ['published_playdead'],
          namingStarted: true,
        ),
        dark: dark,
        nameStep: ArNSCommitStep.approve,
      );
    });
  }
}
