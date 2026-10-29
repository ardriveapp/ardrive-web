import 'dart:ui' as ui;

import 'package:ardrive/models/models.dart';
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

  const labels = [
    'Title',
    'Description',
    'Display name',
    'Keywords',
    'Icon',
    'Cover',
    'Social card',
    'License',
  ];

  for (final (name, size) in [
    ('on a phone', const Size(390, 844)),
    ('on a wide screen', const Size(1280, 900)),
  ]) {
    testWidgets('the license is the last thing filled in, $name',
        (tester) async {
      await pump(tester, size);
      expect(order(tester, labels), labels);
    });
  }
}
