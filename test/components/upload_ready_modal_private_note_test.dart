import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _Ready extends Mock implements UploadReady {}

/// The review dialog has a desktop layout and a phone layout, each with its
/// own copy of the header. The note must show in both for a private drive and
/// in neither for a public one.
void main() {
  const note = 'Files and their names are encrypted before they leave this '
      'device.';

  Future<void> pump(
    WidgetTester tester, {
    required bool uploadIsPublic,
    required Size size,
  }) async {
    final ready = _Ready();
    when(() => ready.uploadIsPublic).thenReturn(uploadIsPublic);
    when(() => ready.numberOfFiles).thenReturn(2);
    when(() => ready.showSettings).thenReturn(false);
    when(() => ready.canShowSettings).thenReturn(false);

    final cubit = MockUploadBloc();
    whenListen(
      cubit,
      const Stream<UploadState>.empty(),
      initialState: ready,
    );

    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: BlocProvider<UploadCubit>.value(
            value: cubit,
            child: Scaffold(
              body: UploadReadyModalBase(
                readyState: ready,
                actions: const [],
                children: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const layouts = {
    'desktop': Size(1200, 900),
    'phone': Size(360, 800),
  };

  for (final entry in layouts.entries) {
    group('${entry.key} layout', () {
      testWidgets('says the files are encrypted for a private drive',
          (tester) async {
        await pump(tester, uploadIsPublic: false, size: entry.value);

        expect(find.text(note), findsOneWidget);
      });

      testWidgets('says nothing of the kind for a public drive',
          (tester) async {
        await pump(tester, uploadIsPublic: true, size: entry.value);

        expect(find.text(note), findsNothing);
      });
    });
  }
}
