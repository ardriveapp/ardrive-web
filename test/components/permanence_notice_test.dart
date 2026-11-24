import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line at the top of a file's details that says whether its data is on
/// the permaweb for good yet.
void main() {
  const dataTxId = 'jF3uAbCdEfGhIjKlMnOpQrStUvWxYz0123456789w7Lp';

  FileDataTableItem item(NetworkTransaction? dataTx) => FileDataTableItem(
        driveId: 'drive',
        fileId: 'file',
        parentFolderId: 'folder',
        name: 'lisbon.jpg',
        size: 1024,
        lastUpdated: DateTime.utc(2026, 6, 1),
        dateCreated: DateTime.utc(2020, 1, 1),
        lastModifiedDate: DateTime.utc(2026, 6, 1),
        contentType: 'image/jpeg',
        dataTxId: dataTxId,
        metadataTx: null,
        dataTx: dataTx,
        pinnedDataOwnerAddress: null,
        index: 0,
        isOwner: true,
      );

  NetworkTransaction tx(
    String status, {
    DateTime? transactionDateCreated,
    DateTime? dateCreated,
  }) =>
      NetworkTransaction(
        id: dataTxId,
        status: status,
        dateCreated: dateCreated ?? DateTime(2025, 1, 1, 12),
        transactionDateCreated: transactionDateCreated,
      );

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
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
          home: Scaffold(body: SizedBox(width: 360, child: child)),
        ),
      ),
    );
  }

  test('says nothing when the status is unknown or the upload failed', () {
    expect(PermanenceNotice.forFile(item(null)), isNull);
    expect(
      PermanenceNotice.forFile(item(tx(TransactionStatus.failed))),
      isNull,
    );
  });

  test('dates a confirmed file by its revision, not the file', () {
    final synced = PermanenceNotice.forFile(item(tx(
      TransactionStatus.confirmed,
      transactionDateCreated: DateTime(2024, 3, 12, 12),
    )))!;
    expect(synced.storedSince, DateTime(2024, 3, 12, 12));

    // Uploaded from this device: only the row's own date is kept.
    final uploaded =
        PermanenceNotice.forFile(item(tx(TransactionStatus.confirmed)))!;
    expect(uploaded.storedSince, DateTime(2025, 1, 1, 12));
  });

  testWidgets('a confirmed file says since when, with its transaction',
      (tester) async {
    await pump(
      tester,
      PermanenceNotice.forFile(item(tx(
        TransactionStatus.confirmed,
        transactionDateCreated: DateTime(2024, 3, 12, 12),
      )))!,
    );

    expect(find.text('Stored permanently since Mar\u00A012,\u00A02024'),
        findsOneWidget);
    expect(find.byKey(const Key('permanenceViewTransaction')), findsOneWidget);
    expect(find.textContaining('View transaction', findRichText: true),
        findsOneWidget);
    expect(find.byType(ArDriveSpinner), findsNothing);
  });

  testWidgets('a pending file says what is happening, not a spinner alone',
      (tester) async {
    await pump(
      tester,
      PermanenceNotice.forFile(item(tx(TransactionStatus.pending)))!,
    );

    expect(find.text('Being stored permanently'), findsOneWidget);
    expect(find.text('Usually within an hour'), findsOneWidget);
    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(find.textContaining('since'), findsNothing);
  });
}
