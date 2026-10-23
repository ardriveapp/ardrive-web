import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive/library/presentation/library_loader/library_loader_cubit.dart';
import 'package:ardrive/library/presentation/library_loader_page.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/mocks.dart';

class _MockLoader extends MockCubit<LibraryLoaderState>
    implements LibraryLoaderCubit {}

const _config = LibraryConfig(
  version: 1,
  driveId: 'c863be1f-a725-4554-9a9e-18268ed8a035',
  rootFolderId: '41520b33-28c1-4892-886b-b845a5709085',
  scope: LibraryDriveScope(),
  privacy: 'public',
  owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
  snapshot: LibrarySnapshot(path: 'snapshot', txId: 't', tags: {}),
  title: 'Library',
  description: '',
  images: LibraryImages(),
  publishedAt: null,
  viewer: null,
);

/// What a library page looks like where it differs from the app.
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

    tearDown(() => LibraryMode.debugSet(null));

    testWidgets('offers editing in the app', (tester) async {
      await pump(tester, note());

      expect(find.byTooltip('Edit note'), findsOneWidget);
    });

    testWidgets('does not on a library page, which is read-only',
        (tester) async {
      LibraryMode.debugSet('library.json');
      await pump(tester, note());

      expect(find.byTooltip('Edit note'), findsNothing);
    });
  });

  testWidgets("a library with no icon of its own shows ArDrive's mark",
      (tester) async {
    await pump(tester, const LibraryIcon(config: null, size: 48));

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      Resources.images.brand.logo1,
    );
  });

  group('the loading screen', () {
    Future<void> showing(WidgetTester tester, LibraryLoaderState state) {
      final loader = _MockLoader();
      whenListen(
        loader,
        const Stream<LibraryLoaderState>.empty(),
        initialState: state,
      );
      return pump(
        tester,
        BlocProvider<LibraryLoaderCubit>.value(
          value: loader,
          child: const LibraryLoaderPage(),
        ),
      );
    }

    Future<void> loading(WidgetTester tester, int received, int? total) =>
        showing(
          tester,
          LibraryLoadingSnapshot(_config, received: received, total: total),
        );

    testWidgets('shows only the background until library.json is read',
        (tester) async {
      await showing(tester, const LibraryLoadingSettings());

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
}
