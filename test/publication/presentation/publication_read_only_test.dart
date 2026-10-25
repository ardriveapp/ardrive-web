import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/publication/presentation/publication_loader_page.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/mocks.dart';

class _MockLoader extends MockCubit<PublicationLoaderState>
    implements PublicationLoaderCubit {}

const _config = PublicationConfig(
  version: 1,
  driveId: 'c863be1f-a725-4554-9a9e-18268ed8a035',
  rootFolderId: '41520b33-28c1-4892-886b-b845a5709085',
  scope: PublicationDriveScope(),
  privacy: 'public',
  owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
  snapshot: PublicationSnapshot(path: 'snapshot', txId: 't', tags: {}),
  title: 'Publication',
  description: '',
  images: PublicationImages(),
  publishedAt: null,
  viewer: null,
);

/// What a publication looks like where it differs from the app.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en', '')],
            home: Scaffold(body: child),
          ),
        ),
      );

  group('a note preview', () {
    Widget note() => SizedBox(
          width: 400,
          height: 600,
          child: DocumentPreviewWidget(
            filename: 'notes.md',
            content: '# Notes',
            contentType: 'text/markdown',
            isSharePage: false,
            fileItem: createMockFileDataTableItem(name: 'notes.md'),
          ),
        );

    tearDown(() => PublicationMode.debugSet(null));

    testWidgets('offers editing in the app', (tester) async {
      await pump(tester, note());

      expect(find.byTooltip('Edit note'), findsOneWidget);
    });

    testWidgets('does not on a publication, which is read-only',
        (tester) async {
      PublicationMode.debugSet('publication.json');
      await pump(tester, note());

      expect(find.byTooltip('Edit note'), findsNothing);
    });
  });

  testWidgets("a publication with no icon of its own shows ArDrive's mark",
      (tester) async {
    await pump(tester, const PublicationIcon(config: null, size: 48));

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      Resources.images.brand.logo1,
    );
  });

  group('the loading screen', () {
    Future<void> showing(WidgetTester tester, PublicationLoaderState state) {
      final loader = _MockLoader();
      whenListen(
        loader,
        const Stream<PublicationLoaderState>.empty(),
        initialState: state,
      );
      return pump(
        tester,
        BlocProvider<PublicationLoaderCubit>.value(
          value: loader,
          child: const PublicationLoaderPage(),
        ),
      );
    }

    Future<void> loading(WidgetTester tester, int received, int? total) =>
        showing(
          tester,
          PublicationLoadingSnapshot(_config, received: received, total: total),
        );

    testWidgets('shows only the background until publication.json is read',
        (tester) async {
      await showing(tester, const PublicationLoadingSettings());

      expect(find.byType(Image), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('says how much of the snapshot has arrived', (tester) async {
      await loading(tester, 1000000, 4000000);

      expect(find.textContaining(' of '), findsOneWidget);
    });

    testWidgets('and only that it is loading when the size is not known',
        (tester) async {
      await loading(tester, 1000000, null);

      expect(find.text('Loading files...'), findsOneWidget);
    });

    testWidgets(
        'or when the browser counted past the size, which was compressed',
        (tester) async {
      await loading(tester, 8000000, 4000000);

      expect(find.text('Loading files...'), findsOneWidget);
    });
  });

  group('the header', () {
    Future<void> header(
      WidgetTester tester, {
      PublicationConfig config = _config,
      bool collapsed = false,
      bool downloadsSelection = false,
    }) {
      final loader = _MockLoader();
      whenListen(
        loader,
        const Stream<PublicationLoaderState>.empty(),
        initialState: PublicationReady(
          config,
          stats: const PublicationStats(fileCount: 79, totalSize: 320794),
        ),
      );
      return pump(
        tester,
        BlocProvider<PublicationLoaderCubit>.value(
          value: loader,
          child: SizedBox(
            width: 1000,
            child: PublicationHeader(
              coverHeight: 200,
              collapsed: collapsed,
              compact: false,
              downloadsSelection: downloadsSelection,
              onDownload: () {},
              onCopyLink: () {},
            ),
          ),
        ),
      );
    }

    PublicationConfig withOwnerName(String? name) => PublicationConfig(
          version: _config.version,
          driveId: _config.driveId,
          rootFolderId: _config.rootFolderId,
          scope: _config.scope,
          privacy: _config.privacy,
          owner: _config.owner,
          ownerName: name,
          snapshot: _config.snapshot,
          title: 'Publication',
          description: 'A description.',
          images: _config.images,
          publishedAt: DateTime.utc(2026, 10, 23),
          viewer: null,
        );

    testWidgets('names its owner by the name they chose', (tester) async {
      await header(tester, config: withOwnerName('Phil'));

      expect(find.text('By Phil'), findsOneWidget);
      // A name is a name, in the body face.
      expect(find.byType(ArDriveIdText), findsNothing);
      expect(find.byTooltip(_config.owner), findsOneWidget);
    });

    testWidgets('or by their address, shortened', (tester) async {
      await header(tester, config: withOwnerName(null));

      // The address is set apart in monospace inside the sentence.
      expect(find.textContaining('By ', findRichText: true), findsWidgets);
      final address = tester.widget<ArDriveIdText>(find.byType(ArDriveIdText));
      expect(address.text, startsWith('iKryOe'));
      expect(address.style.fontFamily, ArDriveMonospace.family);
      expect(find.textContaining('79 files'), findsOneWidget);
      expect(find.text('A description.'), findsOneWidget);
    });

    testWidgets('folds to its title and actions', (tester) async {
      await header(tester, config: withOwnerName(null), collapsed: true);
      await tester.pumpAndSettle();

      expect(find.text('Publication'), findsOneWidget);
      expect(find.text('A description.'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('counts its files even without a publish date', (tester) async {
      await header(tester);

      expect(find.textContaining('79 files'), findsOneWidget);
      expect(find.textContaining('published'), findsNothing);
    });

    testWidgets('downloads what is selected when something is', (tester) async {
      await header(tester, downloadsSelection: true);

      expect(find.text('Download selected'), findsOneWidget);
    });
  });

  testWidgets("a phone's ArDrive mark is a link a screen reader names",
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, const MadeWithArDrive(compact: true));

    expect(find.bySemanticsLabel('Made with ArDrive'), findsOneWidget);
    semantics.dispose();
  });
}
