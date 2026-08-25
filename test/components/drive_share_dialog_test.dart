import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/drive_share_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class MockDriveShareCubit extends MockCubit<DriveShareState>
    implements DriveShareCubit {}

/// What the share drive dialog actually puts on screen.
///
/// These exist because the dialog had no test at all, and the gap showed: it
/// filled its fields from a bloc listener, which never fires for the state a
/// bloc is already in, so a public drive - whose link is built synchronously -
/// rendered an empty link field.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const driveKeyBase64 = 'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E';

  late MockDriveShareCubit cubit;

  Drive drive({required bool isPrivate}) => Drive(
        id: driveId,
        name: 'My Drive',
        ownerAddress: 'owner',
        rootFolderId: 'root',
        privacy:
            isPrivate ? DrivePrivacyTag.private : DrivePrivacyTag.public,
        isHidden: false,
        dateCreated: DateTime.utc(2026, 1, 1),
        lastUpdated: DateTime.utc(2026, 1, 1),
      );

  Widget wrap(Widget child) => ArDriveTheme(
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

  Future<void> pumpState(WidgetTester tester, DriveShareState state) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    whenListen(cubit, const Stream<DriveShareState>.empty(),
        initialState: state);

    await tester.pumpWidget(
      wrap(
        BlocProvider<DriveShareCubit>.value(
          value: cubit,
          child: const DriveShareDialog(),
        ),
      ),
    );
    await tester.pump();
  }

  /// The value shown in a field, whether or not it is masked.
  String fieldText(WidgetTester tester, int index) =>
      tester.widgetList<EditableText>(find.byType(EditableText)).toList()[index]
          .controller
          .text;

  setUp(() => cubit = MockDriveShareCubit());

  group('DriveShareDialog', () {
    testWidgets('a public drive shows its link', (tester) async {
      // The regression that started this file: the public path builds its link
      // synchronously, so the dialog was already in the success state before
      // it could listen for one, and the field came up blank.
      await pumpState(
        tester,
        DriveShareLoadSuccess(
          drive: drive(isPrivate: false),
          driveShareLink:
              Uri.parse('https://app.ardrive.io/#/drives/$driveId?name=My+Drive'),
        ),
      );

      expect(
        fieldText(tester, 0),
        'https://app.ardrive.io/#/drives/$driveId?name=My+Drive',
      );
    });

    testWidgets('a keyless private drive does not claim the link is enough',
        (tester) async {
      // The old copy - "Anyone can access this private drive using the link
      // above" - was written when the key was always embedded. For the keyless
      // default it is simply false, and it is the sharer's only cue about what
      // they still have to send.
      await pumpState(
        tester,
        DriveShareLoadSuccess(
          drive: drive(isPrivate: true),
          driveShareLink:
              Uri.parse('https://app.ardrive.io/#/drives/$driveId'),
          driveKeyBase64: driveKeyBase64,
        ),
      );

      expect(
        find.textContaining('Anyone can access this private drive'),
        findsNothing,
      );
      expect(find.textContaining('The link alone'), findsOneWidget);

      // And the key is offered as its own artifact to send separately.
      expect(find.text('Drive access key'), findsOneWidget);
      expect(fieldText(tester, 1), driveKeyBase64);
    });

    testWidgets('embedding the key retires the separate artifact',
        (tester) async {
      await pumpState(
        tester,
        DriveShareLoadSuccess(
          drive: drive(isPrivate: true),
          driveShareLink: Uri.parse(
            'https://app.ardrive.io/#/drives/$driveId?driveKey=$driveKeyBase64',
          ),
          driveKeyBase64: driveKeyBase64,
          keyIsInLink: true,
        ),
      );

      expect(find.text('Drive access key'), findsNothing);
      expect(
        find.textContaining('Anyone can access this private drive'),
        findsOneWidget,
      );
    });

    testWidgets('a folder share is named after the folder, not the drive',
        (tester) async {
      await pumpState(
        tester,
        DriveShareLoadSuccess(
          drive: drive(isPrivate: false),
          driveShareLink: Uri.parse(
            'https://app.ardrive.io/#/drives/$driveId/folders/folder-id',
          ),
          isFolder: true,
          folderName: 'Q4 Photos',
        ),
      );

      expect(find.text('Share folder with others'), findsOneWidget);
      expect(find.text('Q4 Photos'), findsOneWidget);
      expect(find.text('My Drive'), findsNothing);
    });

    testWidgets('a failure is shown, with a way out of it', (tester) async {
      // The state that used to be unreachable: the dialog spun forever instead.
      await pumpState(tester, const DriveShareLoadFail());

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('couldn’t create a share link'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);
    });
  });
}
