// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:ardrive/blocs/blocs.dart' show LinkVerification;
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/mocks.dart';

final _config = PublicationConfig(
  version: 1,
  driveId: 'c863be1f-a725-4554-9a9e-18268ed8a035',
  rootFolderId: '41520b33-28c1-4892-886b-b845a5709085',
  scope: PublicationDriveScope(),
  privacy: 'public',
  owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
  snapshot: PublicationSnapshot(path: 'snapshot', txId: 't', tags: {}),
  title: 'file-page-check.txt',
  description: '',
  images: PublicationImages(),
  publishedAt: DateTime.utc(2026, 11, 17),
  viewer: null,
);

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  group('the file page head', () {
    Widget head(LinkVerification v) =>
        PublicationFileHead(config: _config, verification: v);

    testWidgets('what follows the badge does not move as it is checked',
        (tester) async {
      final line = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Published'));
      await pump(tester, head(LinkVerification.pending));
      final checking = tester.getSize(line).width;
      await pump(tester, head(LinkVerification.verified));
      expect(tester.getSize(line).width, checking);
    });

    testWidgets('"By" is on the address\'s baseline', (tester) async {
      await pump(tester, head(LinkVerification.verified));
      double baseline(Finder f) {
        final box = tester.renderObject<RenderBox>(f);
        final paragraph = box is RenderParagraph
            ? box
            : tester.renderObject<RenderParagraph>(
                find.descendant(of: f, matching: find.byType(RichText)).first);
        return paragraph.localToGlobal(Offset.zero).dy +
            paragraph.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      }

      final by = baseline(find.text('By'));
      final address = baseline(find.byType(ArDriveIdText));
      expect(by, moreOrLessEquals(address, epsilon: 0.5));
    });
  });

  testWidgets('a short text preview fills its box', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 600,
        height: 400,
        child: DocumentPreviewWidget(
          filename: 'a.txt',
          content: 'one line',
          contentType: 'text/plain',
          isSharePage: true,
          fileItem: createMockFileDataTableItem(name: 'a.txt'),
        ),
      ),
    );
    final text = tester.getRect(find.text('one line'));
    final scroll = tester.getRect(find.byType(SingleChildScrollView).first);
    // The scroll area, whose ground is the preview's own, is the box above the
    // action bar, not the height of its one line.
    expect(scroll.height, greaterThan(text.height * 4));
    final ground = find
        .ancestor(
          of: find.byType(SingleChildScrollView),
          matching:
              find.byWidgetPredicate((w) => w is Container && w.color != null),
        )
        .first;
    expect(tester.getRect(ground).height, scroll.height);
  });
}
