import 'dart:async';

import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/components/create_manifest_form.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockCreateManifestCubit extends MockCubit<CreateManifestState>
    implements CreateManifestCubit {}

/// The new deployment dialog: the folder and the name on one screen, the
/// conflict said in the dialog with its own words, and a failure that stays
/// in the dialog with the way on.
void main() {
  FolderEntry folder(String id, {String? parent, String? name}) => FolderEntry(
        id: id,
        driveId: 'drive-1',
        name: name ?? id,
        parentFolderId: parent,
        path: '',
        dateCreated: DateTime(2024),
        lastUpdated: DateTime(2024),
        isGhost: false,
        isHidden: false,
      );

  late _MockCreateManifestCubit cubit;

  setUp(() {
    cubit = _MockCreateManifestCubit();
    when(() => cubit.checkForConflicts(any())).thenAnswer((_) async {});
    when(() => cubit.reCheckConflicts(any())).thenAnswer((_) async {});
    when(() => cubit.confirmRevision(any())).thenAnswer((_) async {});
    when(() => cubit.retryUpload()).thenAnswer((_) async {});
    when(() => cubit.setFallbackTxId(any())).thenAnswer((_) {});
  });

  Future<void> pumpForm(
    WidgetTester tester,
    CreateManifestState state, {
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    whenListen(
      cubit,
      const Stream<CreateManifestState>.empty(),
      initialState: state,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ActivityTracker(),
        child: ArDriveApp(
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: BlocProvider<CreateManifestCubit>.value(
                  value: cubit,
                  child: const CreateManifestForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  CreateManifestFolderLoadSuccess picker() => CreateManifestFolderLoadSuccess(
        viewingRootFolder: true,
        viewingFolder: FolderWithContents(
          folder: folder('root', name: 'My drive'),
          subfolders: const [],
          files: const [],
        ),
        enableManifestCreationButton: true,
      );

  Finder primary(String text) => find.widgetWithText(ArDriveButtonNew, text);

  group('the folder and the name', () {
    testWidgets('are one screen: a name, then Review with the cost behind it',
        (tester) async {
      await pumpForm(tester, picker());

      expect(find.text('New deployment'), findsOneWidget);
      expect(find.text('Deployment name'), findsOneWidget);
      expect(find.text('My drive'), findsOneWidget, reason: 'the folder');
      expect(find.text('Next'), findsNothing, reason: 'no step for the name');

      final review = tester.widget<ArDriveButtonNew>(primary('Review'));
      expect(review.isDisabled, isTrue, reason: 'a deployment needs a name');

      await tester.enterText(find.byType(TextField).first, 'my-site');
      await tester.pump();

      expect(
        tester.widget<ArDriveButtonNew>(primary('Review')).isDisabled,
        isFalse,
      );

      await tester.tap(primary('Review'));
      await tester.pump();

      verify(() => cubit.checkForConflicts('my-site')).called(1);
    });

    testWidgets('two fast presses of Review make one check', (tester) async {
      final gate = Completer<void>();
      when(() => cubit.checkForConflicts(any())).thenAnswer((_) => gate.future);
      await pumpForm(tester, picker());
      await tester.enterText(find.byType(TextField).first, 'my-site');
      await tester.pump();

      final review = find.widgetWithText(ArDriveButtonNew, 'Review');
      tester.widget<ArDriveButtonNew>(review).onPressed!();
      tester.widget<ArDriveButtonNew>(review).onPressed!();
      await tester.pump();

      verify(() => cubit.checkForConflicts('my-site')).called(1);
      gate.complete();
      await tester.pump();
    });

    testWidgets('never say manifest', (tester) async {
      await pumpForm(tester, picker());

      expect(find.textContaining(RegExp('manifest', caseSensitive: false)),
          findsNothing);
      expect(
        find.textContaining('Arweave address', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('Cancel is the close button, and so is the X', (tester) async {
      await pumpForm(tester, picker());

      expect(find.byType(ArDriveIcon), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        tester.widget<ArDriveButtonNew>(primary('Cancel')).variant,
        ButtonVariant.secondary,
      );
    });

    testWidgets('fit a short phone without overflowing', (tester) async {
      await pumpForm(tester, picker(), size: const Size(360, 560));

      expect(tester.takeException(), isNull);
      expect(primary('Review'), findsOneWidget);
    });
  });

  group('a name that is taken', () {
    testWidgets('by a file or folder asks for another name, in those words',
        (tester) async {
      await pumpForm(
        tester,
        CreateManifestNameConflict(
          conflictingName: 'site',
          parentFolder: folder('root'),
        ),
      );

      expect(find.text('Name already in use'), findsOneWidget);
      expect(
        find.textContaining(
            'A file or folder named “site” is already in this folder.'),
        findsOneWidget,
      );
      expect(find.textContaining('new version'), findsNothing,
          reason: 'that question belongs to a deployment that exists');
      expect(find.byType(ArDriveNotice), findsOneWidget);
      // The name is the same one, so it can't be used again.
      expect(find.text('Cancel'), findsOneWidget);
      expect(primary('Use name'), findsOneWidget);
    });

    testWidgets('by a deployment asks about a new version', (tester) async {
      await pumpForm(
        tester,
        CreateManifestRevisionConfirm(
          existingManifestFileId: 'file-1',
          parentFolder: folder('root'),
        ),
      );

      expect(find.text('Deployment already exists'), findsOneWidget);
      expect(find.textContaining('adds a new version of it'), findsOneWidget);
      expect(find.text('Conflicting deployment was found'), findsNothing);

      await tester.tap(primary('Create new version'));
      await tester.pump();

      verify(() => cubit.confirmRevision(any())).called(1);
    });
  });

  group('a failure', () {
    testWidgets('stays in the dialog, in a notice, with Try again',
        (tester) async {
      await pumpForm(tester, CreateManifestFailure());

      expect(find.text("Couldn't create deployment"), findsOneWidget);
      expect(find.byType(ArDriveNotice), findsOneWidget);
      expect(find.text("The deployment couldn't be uploaded to Arweave."),
          findsOneWidget);
      expect(find.text('Close'), findsWidgets);

      await tester.tap(primary('Try again'));
      await tester.pump();

      verify(() => cubit.retryUpload()).called(1);
      // Still on screen: nothing popped the dialog.
      expect(find.byType(CreateManifestForm), findsOneWidget);
    });

    testWidgets('two fast presses of Try again make one retry', (tester) async {
      final gate = Completer<void>();
      when(() => cubit.retryUpload()).thenAnswer((_) => gate.future);
      await pumpForm(tester, CreateManifestFailure());

      final retry = find.widgetWithText(ArDriveButtonNew, 'Try again');
      tester.widget<ArDriveButtonNew>(retry).onPressed!();
      tester.widget<ArDriveButtonNew>(retry).onPressed!();
      await tester.pump();

      verify(() => cubit.retryUpload()).called(1);
      gate.complete();
      await tester.pump();
    });

    testWidgets('after a post says so, with the transaction, and no Try again',
        (tester) async {
      await pumpForm(
        tester,
        CreateManifestFailure(postedTxId: 'posted-tx', canRetry: false),
      );

      expect(find.textContaining('posted-tx'), findsOneWidget);
      expect(find.textContaining("Don't create it again"), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('of a Turbo payment offers credits, in the dialog',
        (tester) async {
      await pumpForm(tester, CreateManifestFailure(isPaymentError: true));

      expect(find.text('Free allowance used up'), findsOneWidget);
      expect(primary('Buy credits'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('of a changed wallet says nothing was uploaded, no retry',
        (tester) async {
      await pumpForm(tester, CreateManifestWalletMismatch());

      expect(find.textContaining('Nothing was uploaded'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.byType(CreateManifestForm), findsOneWidget);
    });
  });
}
