import 'dart:async';

import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/components/pin_file_dialog.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPin extends MockBloc<PinFileEvent, PinFileState>
    implements PinFileBloc {}

/// The notice for a pin that could not be made stays until the reader tries
/// again or edits the id or the name.
void main() {
  setUpAll(() => registerFallbackValue(const PinFileSubmit()));

  testWidgets('goes when the name is edited', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final bloc = _MockPin();
    final states = StreamController<PinFileState>.broadcast();
    addTearDown(states.close);
    final valid = PinFileFieldsValid(
      id: '01234567-89ab-cdef-0123-456789abcdef',
      name: 'notes',
      nameValidation: NameValidationResult.valid,
      idValidation: IdValidationResult.validEntityId,
      privacy: DrivePrivacy.public,
      dataContentType: 'text/plain',
      dateCreated: DateTime(2024),
      size: 1,
      dataTxId: 'HelloHelloHelloHelloHelloHelloHelloH-+_ABCD',
      pinnedDataOwnerAddress: '0000000000000000000000000000000000000000000',
    );
    whenListen(bloc, states.stream, initialState: valid);
    when(() => bloc.nameTextController)
        .thenReturn(TextEditingController(text: 'notes'));

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
            body: BlocProvider<PinFileBloc>.value(
              value: bloc,
              child: const PinFileDialog(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    states
      ..add(PinFileError(
        id: valid.id,
        name: valid.name,
        nameValidation: NameValidationResult.valid,
        idValidation: IdValidationResult.validEntityId,
      ))
      ..add(valid);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ArDriveNotice), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'notes 2');
    await tester.pump();

    expect(find.byType(ArDriveNotice), findsNothing);
  });
}
