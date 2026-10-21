import 'package:ardrive/authentication/login/blocs/open_drive_cubit.dart';
import 'package:ardrive/authentication/login/views/modals/open_drive_modal.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockOpenDriveCubit extends MockCubit<OpenDriveState>
    implements OpenDriveCubit {}

/// What the "Open a drive" dialog shows for each state the cubit can be in,
/// and what its one button does.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const fileId = 'd5eaed3d-6e5d-7f4e-bd5f-9f4d3e6f7a81';

  late _MockOpenDriveCubit cubit;
  late AppRouterDelegate delegate;

  setUp(() {
    cubit = _MockOpenDriveCubit();
    when(() => cubit.open()).thenAnswer((_) async {});
    when(() => cubit.inputChanged(any())).thenReturn(null);
    when(() => cubit.keyChanged(any())).thenReturn(null);
    when(() => cubit.inputBlurred(any())).thenAnswer((_) async {});
    delegate = AppRouterDelegate();
  });

  tearDown(() => delegate.clearState());

  ArDriveButtonNew openButton(WidgetTester tester) =>
      tester.widget<ArDriveButtonNew>(find.byKey(const Key('openDriveButton')));

  /// The kit forwards a field's key to the TextField inside it, so a key
  /// finds two widgets; the outer one is the one with the controller.
  Finder field(String key) => find.byWidgetPredicate(
        (w) => w is ArDriveTextFieldNew && w.key == Key(key),
      );

  /// Pumps the dialog the way the landing opens it: as a dialog over a page,
  /// so closing it has somewhere to go.
  Future<void> pump(
    WidgetTester tester,
    OpenDriveState initial, {
    Stream<OpenDriveState> stream = const Stream.empty(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    whenListen(cubit, stream, initialState: initial);

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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('openIt'),
                onPressed: () => showDialog<void>(
                  context: context,
                  // The kit's dialog helper puts a Material under its
                  // content; the test does the same.
                  builder: (_) => Material(
                    type: MaterialType.transparency,
                    child: BlocProvider<OpenDriveCubit>.value(
                      value: cubit,
                      child: OpenDriveModal(router: delegate),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('openIt')));
    // Not pumpAndSettle: the looking-up state shows a progress bar that never
    // settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('starts with the field, no key field, and a disabled button',
      (tester) async {
    await pump(tester, const OpenDriveInitial());

    expect(find.text('Open a drive'), findsOneWidget);
    expect(field('openDriveInput'), findsOneWidget);
    expect(field('openDriveKeyInput'), findsNothing);
    expect(openButton(tester).isDisabled, isTrue);
    expect(openButton(tester).text, 'Open drive');
  });

  testWidgets('says what it is looking for', (tester) async {
    await pump(tester, const OpenDriveLookingUp());

    expect(find.text('Looking up drive...'), findsOneWidget);
    expect(openButton(tester).isDisabled, isTrue);
  });

  testWidgets('a public drive is named and can be opened', (tester) async {
    await pump(
      tester,
      const OpenDrivePublic(driveId: driveId, name: 'Family Photos'),
    );

    expect(find.text('Drive found: Family Photos (public)'), findsOneWidget);
    expect(field('openDriveKeyInput'), findsNothing);
    expect(openButton(tester).isDisabled, isFalse);

    await tester.tap(find.byKey(const Key('openDriveButton')));
    await tester.pump();

    verify(() => cubit.open()).called(1);
  });

  testWidgets('a private drive asks for its key and waits', (tester) async {
    await pump(tester, const OpenDrivePrivate(driveId: driveId));

    expect(
      find.text('This is a private drive. Paste the drive key you were given.'),
      findsOneWidget,
    );
    expect(field('openDriveKeyInput'), findsOneWidget);
    expect(openButton(tester).isDisabled, isTrue);
  });

  testWidgets('a rejected key is called out on the key field', (tester) async {
    await pump(
      tester,
      const OpenDrivePrivate(driveId: driveId, keyRejected: true),
    );

    expect(find.text("This key doesn't open this drive."), findsOneWidget);
    expect(openButton(tester).isDisabled, isTrue);
  });

  testWidgets('an accepted key names the drive and can be opened',
      (tester) async {
    await pump(
      tester,
      const OpenDrivePrivate(driveId: driveId, name: 'Tax Returns'),
    );

    expect(find.text('Drive found: Tax Returns (private)'), findsOneWidget);
    expect(openButton(tester).isDisabled, isFalse);
  });

  testWidgets('a key the link carried is shown in the field', (tester) async {
    const rawKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    await pump(
      tester,
      const OpenDrivePrivate(driveId: driveId, prefilledKey: rawKey),
    );

    final keyField = tester.widget<ArDriveTextFieldNew>(
      field('openDriveKeyInput'),
    );
    expect(keyField.controller!.text, rawKey);
  });

  testWidgets('a drive that does not exist says so', (tester) async {
    await pump(tester, const OpenDriveNotFound());

    expect(
      find.text(
        'No drive was found for that ID. Check the link, or ask whoever '
        'shared it.',
      ),
      findsOneWidget,
    );
    expect(openButton(tester).isDisabled, isTrue);
  });

  testWidgets('a gateway that cannot be reached says so', (tester) async {
    await pump(tester, const OpenDriveNetworkError());

    expect(
      find.text(
        "Couldn't reach the network. Check your connection and try again.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('text that is neither a link nor an id says so', (tester) async {
    await pump(tester, const OpenDriveUnrecognisedInput());

    expect(
      find.text("That doesn't look like an ArDrive link or drive ID."),
      findsOneWidget,
    );
  });

  testWidgets('a file link changes the button and goes straight to the file',
      (tester) async {
    await pump(
      tester,
      OpenDriveOtherLink(
        route: AppRoutePath.sharedFile(sharedFileId: fileId),
        isFile: true,
      ),
    );

    expect(find.text("That's a link to a file."), findsOneWidget);
    expect(openButton(tester).text, 'Open file');
    expect(openButton(tester).isDisabled, isFalse);

    await tester.tap(find.byKey(const Key('openDriveButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Open a drive'), findsNothing);
    expect(delegate.sharedFileId, fileId);
    verifyNever(() => cubit.open());
  });

  testWidgets('once the drive is written, closes and shows it', (tester) async {
    await pump(
      tester,
      const OpenDrivePublic(driveId: driveId, name: 'Family Photos'),
      stream: Stream.fromIterable([
        const OpenDriveOpening(),
        const OpenDriveOpened(driveId: driveId),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Open a drive'), findsNothing);
    expect(delegate.driveId, driveId);
    expect(delegate.signingIn, isFalse);
    expect(delegate.syncOnOpenDriveId, driveId);
  });
}
