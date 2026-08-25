import 'dart:typed_data';

import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/blocs/fs_entry_preview/image_preview_notification.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFsEntryPreviewCubit extends Mock implements FsEntryPreviewCubit {}

/// What the bar under an image preview is allowed to spend.
///
/// The share page and the file explorer share this widget but do not share
/// their surroundings, and the bar is sized for the explorer's: a name over a
/// type, on a 96px floor. On the share page both of those are already on the
/// card - the name beside the thumbnail, the type in File details - so inline
/// there the bar is only Expand.
void main() {
  Widget wrap(Widget child) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(body: child),
      ),
    );
  }

  // A 1x1 GIF, so the image itself decodes rather than erroring into a state
  // that would take the bar down with it.
  final pixel = Uint8List.fromList([
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, //
    0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
  ]);

  Future<void> pumpPreview(WidgetTester tester, {required bool isSharePage}) {
    FsEntryPreviewCubit.imagePreviewNotifier.value = ImagePreviewNotification(
      dataBytes: pixel,
      filename: 'Sunset over the bay.png',
      contentType: 'image/png',
    );

    return tester.pumpWidget(wrap(
      SizedBox(
        height: 430,
        width: 580,
        child: ImagePreviewWidget(
          isSharePage: isSharePage,
          isFullScreen: false,
          canNavigateThroughImages: false,
          previewCubit: MockFsEntryPreviewCubit(),
        ),
      ),
    ));
  }

  tearDown(() => FsEntryPreviewCubit.imagePreviewNotifier.value = null);

  testWidgets('on the share page the bar is only Expand', (tester) async {
    await pumpPreview(tester, isSharePage: true);

    expect(find.byTooltip('Expand'), findsOneWidget);
    // Neither of the two things the card already says.
    expect(find.text('Sunset over the bay'), findsNothing);
    expect(find.text('PNG'), findsNothing);
  });

  testWidgets('the file explorer keeps the name and the type', (tester) async {
    await pumpPreview(tester, isSharePage: false);

    expect(find.byTooltip('Expand'), findsOneWidget);
    expect(find.text('Sunset over the bay'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
  });

  testWidgets('the share page bar leaves the image more room', (tester) async {
    await pumpPreview(tester, isSharePage: false);
    final explorerImage = tester.getSize(find.byType(Flexible).first).height;

    await pumpPreview(tester, isSharePage: true);
    final shareImage = tester.getSize(find.byType(Flexible).first).height;

    expect(shareImage, greaterThan(explorerImage),
        reason: 'the room the bar gives back should reach the image');
  });
}
