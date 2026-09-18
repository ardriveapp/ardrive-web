import 'package:ardrive/models/models.dart';
import 'package:ardrive/upload_entry/presentation/upload_destination_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Drive _drive(String id, String name, {String privacy = 'private'}) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: name,
      privacy: privacy,
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// Choosing where an upload goes, and being told to make a drive first.
void main() {
  final photos = _drive('photos', 'Photos');
  final website = _drive('website', 'Website', privacy: 'public');
  final archive = _drive('archive', 'Archive');

  Future<void> open(WidgetTester tester, WidgetBuilder dialog) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(context: context, builder: dialog),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('choosing a drive', () {
    late List<Drive> selected;

    setUp(() => selected = []);

    Future<void> openChooser(
      WidgetTester tester, {
      Set<String> unsynced = const {},
    }) =>
        open(
          tester,
          (_) => UploadDestinationDialog(
            drives: [website, photos, archive],
            unsyncedDriveIds: unsynced,
            onSelect: selected.add,
          ),
        );

    testWidgets('lists the drives in the order given', (tester) async {
      await openChooser(tester);

      expect(find.text('Upload to which drive?'), findsOneWidget);

      final website = tester.getTopLeft(find.text('Website')).dy;
      final photos = tester.getTopLeft(find.text('Photos')).dy;
      final archive = tester.getTopLeft(find.text('Archive')).dy;

      expect(website, lessThan(photos));
      expect(photos, lessThan(archive));
    });

    /// Public or private is the choice nobody can take back, so every row
    /// says it in words.
    testWidgets('says which drives are public', (tester) async {
      await openChooser(tester);

      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Private'), findsNWidgets(2));
    });

    testWidgets('marks only the drives nothing has read', (tester) async {
      await openChooser(tester, unsynced: {archive.id});

      expect(find.text('Never synced'), findsOneWidget);

      final hint = tester.getTopLeft(find.text('Never synced')).dy;
      expect(hint, greaterThan(tester.getTopLeft(find.text('Archive')).dy));
    });

    testWidgets('closes and hands over the drive that was tapped',
        (tester) async {
      await openChooser(tester);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(selected, [photos]);
      expect(find.text('Upload to which drive?'), findsNothing);
    });

    testWidgets('can be cancelled without choosing', (tester) async {
      await openChooser(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selected, isEmpty);
      expect(find.text('Upload to which drive?'), findsNothing);
    });
  });

  group('with no drive to upload to', () {
    late int created;

    setUp(() => created = 0);

    Future<void> openNeedsDrive(WidgetTester tester) => open(
          tester,
          (_) => UploadNeedsDriveDialog(onCreateDrive: () => created++),
        );

    testWidgets('says that files live in drives', (tester) async {
      await openNeedsDrive(tester);

      expect(find.text('Create a drive first'), findsOneWidget);
      expect(
        find.text(
          'Your files are kept in drives. Create one to start uploading.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('closes and starts a new drive', (tester) async {
      await openNeedsDrive(tester);

      await tester.tap(find.text('New Drive'));
      await tester.pumpAndSettle();

      expect(created, 1);
      expect(find.text('Create a drive first'), findsNothing);
    });

    testWidgets('can be cancelled without making one', (tester) async {
      await openNeedsDrive(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(created, 0);
      expect(find.text('Create a drive first'), findsNothing);
    });
  });
}
