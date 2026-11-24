import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/blocs/fs_entry_preview/image_preview_notification.dart';
import 'package:ardrive/pages/drive_detail/components/full_screen_preview_request.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../gallery/explorer/gallery_test_items.dart';

class MockFsEntryPreviewCubit extends Mock implements FsEntryPreviewCubit {}

/// Moving through photos in the preview: the arrows, the keys, and the ends.
void main() {
  final pixel = Uint8List.fromList([
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, //
    0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
  ]);

  late int next, previous;
  late bool hasNext, hasPrevious;

  setUp(() {
    next = 0;
    previous = 0;
    hasNext = true;
    hasPrevious = true;
    FsEntryPreviewCubit.imagePreviewNotifier.value = ImagePreviewNotification(
      dataBytes: pixel,
      filename: 'Pier.png',
      contentType: 'image/png',
    );
  });
  tearDown(() {
    FsEntryPreviewCubit.imagePreviewNotifier.value = null;
    FullScreenPreviewRequest.cancel();
  });

  final photo = fileItem('pier');
  MockFsEntryPreviewCubit cubitFor(FileDataTableItem item) {
    final cubit = MockFsEntryPreviewCubit();
    when(() => cubit.maybeSelectedItem).thenReturn(item);
    return cubit;
  }

  ImagePreviewWidget preview(
          {required bool fullScreen, FileDataTableItem? item}) =>
      ImagePreviewWidget(
        isFullScreen: fullScreen,
        canNavigateThroughImages: true,
        onNextImageNavigate: () => next++,
        onPreviousImageNavigate: () => previous++,
        hasNextImage: () => hasNext,
        hasPreviousImage: () => hasPrevious,
        previewCubit: cubitFor(item ?? photo),
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(body: child),
      ),
    ));
    await tester.pump();
  }

  bool visible(WidgetTester tester, String tooltip) => tester
      .widget<Visibility>(find
          .ancestor(
              of: find.byTooltip(tooltip, skipOffstage: false),
              matching: find.byType(Visibility))
          .first)
      .visible;

  testWidgets('at the last photo the next arrow goes; the previous stays',
      (tester) async {
    hasNext = false;
    await pump(tester, preview(fullScreen: false));
    expect(visible(tester, 'Next image'), isFalse);
    expect(visible(tester, 'Previous image'), isTrue);
  });

  testWidgets('full screen: the arrow keys move, but not past an end',
      (tester) async {
    await pump(tester, preview(fullScreen: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(next, 1);
    expect(previous, 1);

    hasNext = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(next, 1);
  });

  testWidgets('full screen: Escape closes it', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(body: preview(fullScreen: true)))),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewWidget), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewWidget), findsNothing);
  });

  testWidgets(
      'a view that asks for full screen gets it, and hears when it closes',
      (tester) async {
    var closed = 0;
    FullScreenPreviewRequest.request(fileId: 'pier', onClosed: () => closed++);
    await pump(tester, preview(fullScreen: false));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is ImagePreviewWidget && w.isFullScreen),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('a request for another photo is not taken by this one',
      (tester) async {
    FullScreenPreviewRequest.request(fileId: 'someone else');
    await pump(tester, preview(fullScreen: false));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is ImagePreviewWidget && w.isFullScreen),
        findsNothing);
  });

  testWidgets('full screen on a photo too large to load unasked offers Preview',
      (tester) async {
    var asked = 0;
    FsEntryPreviewCubit.imagePreviewNotifier.value = ImagePreviewNotification(
      filename: 'Huge.jpg',
      contentType: 'image/jpeg',
      onRequestSize: 30 * 1024 * 1024,
      loadOnRequest: () => asked++,
    );
    await pump(tester, preview(fullScreen: true));
    await tester.tap(find.text('Preview'));
    expect(asked, 1);
  });

  testWidgets('full screen: a tap brings the hidden controls back',
      (tester) async {
    await pump(tester, preview(fullScreen: true));
    // They hide on their own after a few seconds.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 0);
    await tester.tapAt(const Offset(640, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  test('a request is dropped for its own photo only', () {
    FullScreenPreviewRequest.request(fileId: 'a');
    FullScreenPreviewRequest.cancelFor('b');
    expect(FullScreenPreviewRequest.take('a'), isNotNull);
    FullScreenPreviewRequest.request(fileId: 'a');
    FullScreenPreviewRequest.cancelFor('a');
    expect(FullScreenPreviewRequest.take('a'), isNull);
  });

  testWidgets('without a request the preview stays inline', (tester) async {
    await pump(tester, preview(fullScreen: false));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is ImagePreviewWidget && w.isFullScreen),
        findsNothing);
  });
}
