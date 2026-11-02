import 'dart:ui' as ui;

import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_look_step.dart';
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

void main() {
  late _MockPublishCubit cubit;

  setUp(() async {
    cubit = _MockPublishCubit();
    when(() => cubit.state)
        .thenReturn(const PublishState(stage: PublishStage.look, title: 'A'));
    when(() => cubit.drive).thenReturn(Drive(
      id: 'drive',
      rootFolderId: 'root',
      ownerAddress: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      name: 'Drive',
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime.utc(2026),
      lastUpdated: DateTime.utc(2026),
    ));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final mark = await recorder.endRecording().toImage(4, 4);
    when(() => cubit.mark()).thenAnswer((_) async => mark);
    when(() => cubit.isPrivateFile).thenReturn(false);
    when(() => cubit.isFile).thenReturn(false);
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlocProvider<PublishCubit>.value(
                value: cubit,
                child: const PublishLookStep(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The form's labels, top to bottom.
  List<String> order(WidgetTester tester, List<String> labels) {
    final found = {
      for (final label in labels)
        label: tester.getTopLeft(find.text(label, skipOffstage: false).first).dy
    };
    return [...labels]..sort((a, b) => found[a]!.compareTo(found[b]!));
  }

  Future<void> openMore(WidgetTester tester) async {
    await tester.ensureVisible(find.text('More options'));
    await tester.pump();
    await tester.tap(find.text('More options'));
    await tester.pump();
  }

  const everyLabel = [
    'Title',
    'Description',
    'Cover',
    'Icon',
    'Display name',
    'Keywords',
    'Social card',
    'License',
  ];
  const hidden = ['Display name', 'Keywords', 'Social card', 'License'];

  for (final (name, size) in [
    ('on a phone', const Size(390, 844)),
    ('on a wide screen', const Size(1280, 900)),
  ]) {
    testWidgets('the pictures sit right under the words, $name',
        (tester) async {
      await pump(tester, size);
      await openMore(tester);
      await tester.pump();
      expect(order(tester, everyLabel), everyLabel);
    });
  }

  testWidgets(
      'display name, keywords, social card and license wait behind '
      'More options', (tester) async {
    await pump(tester, const Size(1280, 900));

    for (final label in ['Title', 'Description', 'Cover', 'Icon']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('More options'), findsOneWidget);
    for (final label in hidden) {
      expect(find.text(label), findsNothing, reason: label);
    }

    await openMore(tester);
    for (final label in hidden) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('More options starts open when one has a value', (tester) async {
    when(() => cubit.state).thenReturn(const PublishState(
        stage: PublishStage.look, title: 'A', ownerName: 'Maya'));
    await pump(tester, const Size(1280, 900));

    for (final label in hidden) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the image hints say they are optional', (tester) async {
    await pump(tester, const Size(1280, 900));
    await openMore(tester);

    expect(
        find.text(
            'Optional. Best at 1600 by 400 pixels; phones crop the sides.'),
        findsOneWidget);
    expect(find.text('Optional. Square, at least 512 pixels wide.'),
        findsOneWidget);
    expect(
        find.textContaining(
            'Optional. Best at 1200 by 630 pixels. Until you pick one'),
        findsOneWidget);
  });

  group('the page preview', () {
    Future<PickedImage> picked() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      return PickedImage(
        preview: await recorder.endRecording().toImage(4, 4),
        image: const NewPublicationImage({}),
      );
    }

    testWidgets('cuts the icon into the cover, the title beside it',
        (tester) async {
      final cover = await tester.runAsync(picked);
      final icon = await tester.runAsync(picked);
      when(() => cubit.state).thenReturn(PublishState(
        stage: PublishStage.look,
        title: 'Field recordings',
        cover: cover,
        icon: icon,
      ));
      await pump(tester, const Size(1280, 900));

      // The form's own thumbnails are other sizes: the preview's icon is the
      // 40 px one, and its cover the 4:1 one.
      final rects = [
        for (final e in find.byType(RawImage, skipOffstage: false).evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      final iconRect =
          rects.singleWhere((r) => r.size == const Size.square(40));
      final coverRect = rects.singleWhere((r) => r.width / r.height == 4);
      expect(iconRect.size, const Size.square(40));
      // Centred on the cover's bottom edge.
      expect(iconRect.top, lessThan(coverRect.bottom));
      expect(iconRect.bottom, greaterThan(coverRect.bottom));
      expect(iconRect.left - coverRect.left, 12 + 3);
      final title = tester.getRect(find
          .byWidgetPredicate((w) => w is Text && w.data == 'Field recordings'));
      expect(title.left, greaterThanOrEqualTo(iconRect.right + 3 + 12));
      expect(title.top, greaterThan(coverRect.bottom));
      expect(title.top, lessThan(iconRect.bottom));
    });

    testWidgets('shows the wallet icon and the address in the byline',
        (tester) async {
      when(() => cubit.state).thenReturn(const PublishState(
          stage: PublishStage.look, title: 'A', ownerName: 'Maya'));
      await pump(tester, const Size(390, 844));

      expect(find.text('By Maya', skipOffstage: false), findsOneWidget);
      expect(
          find.byIcon(Icons.account_balance_wallet_outlined,
              skipOffstage: false),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a file page', () {
    setUp(() {
      when(() => cubit.isFile).thenReturn(true);
      when(() => cubit.scopeName).thenReturn('Lake.jpg');
    });

    testWidgets('the page preview shows its file under the header',
        (tester) async {
      await pump(tester, const Size(1400, 1000));

      expect(find.text('Lake.jpg', skipOffstage: false), findsOneWidget);
      expect(find.text('Download', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('files', skipOffstage: false), findsNothing);
    });

    testWidgets("a private file's name stays out of the preview",
        (tester) async {
      when(() => cubit.isPrivateFile).thenReturn(true);
      await pump(tester, const Size(1400, 1000));

      expect(find.text('Lake.jpg', skipOffstage: false), findsNothing);
      expect(find.text('Encrypted file', skipOffstage: false), findsOneWidget);
      expect(find.text('From this drive', skipOffstage: false), findsNothing);
    });
  });
}
