@Tags(['measurement'])
library;

// Screenshots of the app's tags, badges and status text, for review. Not an
// assertion: run with
// flutter test test/components/tags_screens_test.dart --run-skipped --tags=measurement
// and find the PNGs in build/tag-shots. The names page and the name chip are
// in test/arns/arns_screens_test.dart.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_view.dart';
import 'package:ardrive/blocs/shared_file/shared_file_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _outDir = Directory('build/tag-shots');

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
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await (FontLoader('MaterialIcons')
        ..addFont(_read(
            '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
  ArDriveMonospace.readFont = () => _read('$dir/mono/RobotoMono-Regular.ttf');
  await ArDriveMonospace.ensureLoaded();
}

FileRevision _revision(String txId, DateTime at) => FileRevision(
      fileId: 'file',
      driveId: 'drive',
      name: 'Annual report.pdf',
      parentFolderId: 'root',
      size: 2400000,
      lastModifiedDate: at,
      metadataTxId: '$txId-meta',
      dataTxId: txId,
      dateCreated: at,
      action: 'upload',
      isHidden: false,
    );

void main() {
  setUpAll(_loadFonts);

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget Function(BuildContext context) build, {
    required bool phone,
    required bool dark,
    double height = 420,
  }) async {
    final size = phone ? Size(390, height) : Size(1000, height);
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
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: build(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${_outDir.path}/$name-${phone ? '390' : 'desktop'}-${dark ? 'dark' : 'light'}.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // Disposes anything holding a timer.
    await tester.pumpWidget(const SizedBox());
  }

  Widget label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
          ),
        ),
      );

  for (final phone in [false, true]) {
    for (final dark in [true, false]) {
      final suffix = '${phone ? '390' : 'desktop'} ${dark ? 'dark' : 'light'}';

      testWidgets('drive row and link verification, $suffix', (tester) async {
        await capture(
          tester,
          '01-drive-row-and-verification',
          (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(context, 'Drive shared with you'),
              DriveListRow(
                drive: DriveListItem(
                  id: 'd',
                  name: 'Team photos',
                  isPrivate: false,
                  isSharedWithMe: true,
                  isHidden: false,
                  dateCreated: DateTime(2025, 3, 4),
                  hasBeenWalked: true,
                  fileCount: 120,
                  totalSize: 4200000,
                  lastSyncedAt: DateTime.now(),
                  isSyncing: false,
                  lastSyncFailed: false,
                ),
                onOpen: () {},
                showsColumns: !phone,
              ),
              label(context, 'Shared file link check'),
              for (final v in LinkVerification.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SharedFileVerificationBadge(verification: v),
                ),
            ],
          ),
          phone: phone,
          dark: dark,
          height: 460,
        );
      });

      testWidgets('shared file versions, $suffix', (tester) async {
        final older = _revision('older', DateTime(2026, 3, 1));
        final newer = _revision('newer', DateTime(2026, 9, 1));
        await capture(
          tester,
          '02-shared-file-versions',
          (context) => SizedBox(
            width: 342,
            child: SharedFileVersionsContent(
              revisions: [newer, older],
              status: SharedFileActivityStatus.loaded,
              sharedRevision: older,
              currentRevision: older,
              onOpened: () {},
              onSelected: (_) {},
            ),
          ),
          phone: phone,
          dark: dark,
          height: 300,
        );
      });

      testWidgets('sync summary, $suffix', (tester) async {
        for (final error in [false, true]) {
          await capture(
            tester,
            '03-sync-summary-${error ? 'error' : 'done'}',
            (context) => Align(
              alignment: Alignment.topRight,
              child: SyncSummaryFlash(
                announcement: SyncAnnouncement(
                  identity: error,
                  showFor: const Duration(hours: 1),
                  lead: error
                      ? 'Synced 10 of 12 drives'
                      : 'Synced 12 drives, 3 new files',
                  trailing: error ? '2 drives could not be read' : null,
                  isError: error,
                ),
                child: const SizedBox(width: 120, height: 40),
              ),
            ),
            phone: phone,
            dark: dark,
            height: 200,
          );
        }
      });
    }
  }
}
