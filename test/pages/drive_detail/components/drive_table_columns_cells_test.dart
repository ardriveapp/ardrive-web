import 'package:ardrive/components/components.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the Type, Transaction ID and Status cells of a row hold, for a file
/// and for a folder.
void main() {
  const txId = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
  final epoch = DateTime(2026, 1, 1);

  FileDataTableItem file({String? status}) => FileDataTableItem(
        driveId: 'drive',
        lastUpdated: epoch,
        name: 'photo.png',
        size: 10,
        dateCreated: epoch,
        contentType: 'image/png',
        fileStatusFromTransactions: status,
        index: 0,
        isOwner: true,
        fileId: 'file',
        parentFolderId: 'root',
        dataTxId: txId,
        lastModifiedDate: epoch,
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
      );

  final folder = FolderDataTableItem(
    driveId: 'drive',
    folderId: 'folder',
    name: 'Photos',
    lastUpdated: epoch,
    dateCreated: epoch,
    contentType: 'folder',
    index: 0,
    isOwner: true,
  );

  /// The row built the way the explorer builds it, its three new cells laid
  /// out side by side.
  Future<void> pump(WidgetTester tester, ArDriveDataTableItem item) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: Builder(builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              final tile = DriveExplorerItemTile(
                name: item.name,
                size: '10 B',
                lastUpdated: epoch,
                dateCreated: epoch,
                license: '',
                type: driveTableTypeLabel(
                  l10n,
                  driveTableType(
                    contentType: item.contentType,
                    name: item.name,
                  ),
                ),
                transactionId: driveTableTransactionId(item),
                status: driveTableStatusLabel(
                  l10n,
                  item.fileStatusFromTransactions,
                ),
                statusValue: item.fileStatusFromTransactions,
                onPressed: () {},
                isHidden: false,
                typography: ArDriveTypographyNew.of(context),
                dataTableItem: item,
                colorTokens: ArDriveTheme.of(context).themeData.colorTokens,
              );
              return Row(
                children: [
                  for (final cell in tile.row.sublist(ColumnIndexes.type))
                    Expanded(child: cell),
                ],
              );
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a file shows its type, short transaction ID and status',
      (tester) async {
    await pump(tester, file(status: TransactionStatus.confirmed));

    expect(find.text('PNG image'), findsOneWidget);
    expect(find.text(shortenId(txId)), findsOneWidget);
    expect(find.text('Permanent'), findsOneWidget);
    // The full ID is never drawn, only offered to copy.
    expect(find.text(txId), findsNothing);
  });

  testWidgets('the transaction ID is in the ID style, with a copy button',
      (tester) async {
    await pump(tester, file(status: TransactionStatus.confirmed));

    expect(find.byType(ArDriveIdText), findsOneWidget);
    expect(find.byType(CopyButton), findsOneWidget);
    expect(tester.widget<CopyButton>(find.byType(CopyButton)).text, txId);
  });

  testWidgets('a pending and a failed file say so', (tester) async {
    await pump(tester, file(status: TransactionStatus.pending));
    expect(find.text('Pending'), findsOneWidget);

    await pump(tester, file(status: TransactionStatus.failed));
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('a folder shows its type and leaves the other two empty',
      (tester) async {
    await pump(tester, folder);

    expect(find.text('Folder'), findsOneWidget);
    expect(find.byType(ArDriveIdText), findsNothing);
    expect(find.byType(CopyButton), findsNothing);
    expect(find.byType(FileStatusDot), findsNothing);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('Permanent'), findsNothing);
    expect(find.text('Failed'), findsNothing);
  });

  testWidgets('a file with no status yet leaves the status empty',
      (tester) async {
    await pump(tester, file());

    expect(find.text('PNG image'), findsOneWidget);
    expect(find.byType(FileStatusDot), findsNothing);
  });
}
