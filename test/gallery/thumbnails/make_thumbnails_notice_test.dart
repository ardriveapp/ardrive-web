import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/gallery/thumbnails/make_thumbnails_notice.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/locked_drive_fixtures.dart';
import '../../test_utils/mocks.dart';
import '../explorer/gallery_test_items.dart';

const photo = 3 * 1024 * 1024;

void main() {
  final drive = Drive(
    id: 'drive',
    rootFolderId: 'root',
    name: 'Photos',
    ownerAddress: 'owner',
    dateCreated: DateTime(2026, 1, 1),
    lastUpdated: DateTime(2026, 1, 1),
    privacy: 'public',
    isHidden: false,
  );
  final folder = createMockFolderEntry(id: 'trips', name: 'Trips');

  Variant v(int w, int h) =>
      Variant(name: 'x', txId: 't$w$h', size: 1000, width: w, height: h);

  Future<void> pump(WidgetTester tester, List<ArDriveDataTableItem> items,
      MemoryKeyValueStore store) async {
    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MakeThumbnailsNotice(
            items: items,
            drive: drive,
            folder: folder,
            store: store,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('imagesNeedingThumbnails', () {
    test('counts images with none, and photos with only the small one', () {
      expect(
          imagesNeedingThumbnails([
            fileItem('a'),
            fileItem('b', size: photo, variants: [v(100, 66)]),
            fileItem('c', size: photo, variants: [v(100, 66), v(512, 341)]),
            fileItem('d', contentType: 'application/pdf'),
            fileItem('e', isHidden: true),
            folderItem('f'),
          ]),
          2);
    });
  });

  testWidgets('says how many need thumbnails, with Make thumbnails and Not now',
      (tester) async {
    await pump(tester, [fileItem('a'), fileItem('b')], MemoryKeyValueStore());
    expect(find.text('2 images here need thumbnails.'), findsOneWidget);
    expect(find.text('Make thumbnails'), findsOneWidget);
    // The design system's close button, labelled Not now.
    expect(find.byTooltip('Not now'), findsOneWidget);
  });

  testWidgets('Not now hides it, and it stays hidden for that folder',
      (tester) async {
    final store = MemoryKeyValueStore();
    await pump(tester, [fileItem('a')], store);
    await tester.tap(find.byTooltip('Not now'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('make-thumbnails-notice')), findsNothing);

    // Opened again later.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, [fileItem('a')], store);
    expect(find.byKey(const ValueKey('make-thumbnails-notice')), findsNothing);
  });

  testWidgets('nothing when every image has what it needs', (tester) async {
    await pump(
        tester,
        [
          fileItem('c', size: photo, variants: [v(100, 66), v(512, 341)])
        ],
        MemoryKeyValueStore());
    expect(find.byKey(const ValueKey('make-thumbnails-notice')), findsNothing);
  });

  testWidgets('nothing for someone who does not own the drive', (tester) async {
    final notMine = FileDataTableItem(
      driveId: 'drive',
      lastUpdated: DateTime(2026),
      name: 'a.jpg',
      size: 1000,
      dateCreated: DateTime(2026),
      contentType: 'image/jpeg',
      index: 0,
      isOwner: false,
      fileId: 'a',
      parentFolderId: 'trips',
      dataTxId: 'tx-a',
      lastModifiedDate: DateTime(2026),
      metadataTx: null,
      dataTx: null,
      pinnedDataOwnerAddress: null,
    );
    await pump(tester, [notMine], MemoryKeyValueStore());
    expect(find.byKey(const ValueKey('make-thumbnails-notice')), findsNothing);
  });
}
