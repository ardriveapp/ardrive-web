import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

/// The line at the top of a file's details that says whether its data is on
/// the permaweb for good yet.
void main() {
  const txId = 'jF3uAbCdEfGhIjKlMnOpQrStUvWxYz0123456789w7Lp';
  final now = DateTime(2026, 11, 24, 12);

  PermanenceNotice? noticeFor(String? status, DateTime? firstStored) =>
      PermanenceLine.noticeFor(
        txId: txId,
        status: status,
        firstStored: firstStored,
        now: now,
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
    expect(noticeFor(null, DateTime(2024)), isNull);
    expect(noticeFor(TransactionStatus.failed, DateTime(2024)), isNull);
    expect(noticeFor(TransactionStatus.confirmed, null), isNull);
  });

  test('a confirmed file is dated by its first revision with the data', () {
    final notice =
        noticeFor(TransactionStatus.confirmed, DateTime(2024, 3, 12, 12))!;
    expect(notice.storedSince, DateTime(2024, 3, 12, 12));
  });

  test('only a recent upload says it is on its way', () {
    final recent = noticeFor(
      TransactionStatus.pending,
      now.subtract(const Duration(minutes: 20)),
    );
    expect(recent, isNotNull);
    expect(recent!.storedSince, isNull);

    // A first sync marks old files pending until the gateway answers.
    expect(
      noticeFor(
          TransactionStatus.pending, now.subtract(const Duration(days: 3))),
      isNull,
    );
  });

  testWidgets('a confirmed file says since when, with its transaction',
      (tester) async {
    await pump(
      tester,
      PermanenceNotice(txId: txId, storedSince: DateTime(2024, 3, 12, 12)),
    );

    expect(
      find.text('Stored permanently since Mar 12, 2024'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('permanenceViewTransaction')), findsOneWidget);
    expect(
      find.textContaining('View transaction', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ArDriveSpinner), findsNothing);
  });

  testWidgets('a pending file says what is happening, not a spinner alone',
      (tester) async {
    await pump(tester, const PermanenceNotice(txId: txId, storedSince: null));

    expect(find.text('Being stored permanently'), findsOneWidget);
    expect(find.text('Usually within an hour'), findsOneWidget);
    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(find.textContaining('since'), findsNothing);
  });

  testWidgets('a new version starts with nothing, not the old data\'s date',
      (tester) async {
    final feeds = {
      'old-tx': BehaviorSubject<({String? status, DateTime? firstStored})>(),
      'new-tx': BehaviorSubject<({String? status, DateTime? firstStored})>(),
    };
    PermanenceLine.watch = (_, txId) => feeds[txId]!.stream;
    addTearDown(() {
      PermanenceLine.watch = defaultPermanenceWatch;
      for (final f in feeds.values) {
        f.close();
      }
    });

    FileDataTableItem version(String txId) => FileDataTableItem(
          driveId: 'drive',
          fileId: 'file',
          parentFolderId: 'folder',
          name: 'lisbon.jpg',
          size: 1,
          lastUpdated: now,
          dateCreated: now,
          lastModifiedDate: now,
          contentType: 'image/jpeg',
          dataTxId: txId,
          metadataTx: null,
          dataTx: NetworkTransaction(
            id: txId,
            status: TransactionStatus.pending,
            dateCreated: now,
          ),
          pinnedDataOwnerAddress: null,
          index: 0,
          isOwner: true,
        );

    feeds['old-tx']!.add((
      status: TransactionStatus.confirmed,
      firstStored: DateTime(2024, 3, 12),
    ));
    await pump(tester, PermanenceLine(item: version('old-tx')));
    await tester.pump();
    expect(find.byKey(const Key('permanenceStored')), findsOneWidget);

    // Same widget, same place: only the data changed.
    await pump(tester, PermanenceLine(item: version('new-tx')));
    await tester.pump();
    expect(find.byKey(const Key('permanenceStored')), findsNothing);
  });
}
