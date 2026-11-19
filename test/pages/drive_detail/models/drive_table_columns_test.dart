import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

/// The explorer's Type, Transaction ID and Status columns: what a row calls
/// itself, when each is shown, and how each sorts.
void main() {
  final l10n = AppLocalizationsEn();

  String type(String contentType, [String name = 'file']) =>
      driveTableTypeLabel(
        l10n,
        driveTableType(contentType: contentType, name: name),
      );

  group('the Type label', () {
    test('names a folder', () {
      expect(type('folder', 'Photos'), 'Folder');
    });

    test('names the common formats', () {
      expect(type('application/pdf'), 'PDF');
      expect(type('image/png'), 'PNG image');
      expect(type('image/jpeg'), 'JPEG image');
      expect(type('image/gif'), 'GIF image');
      expect(type('image/svg+xml'), 'SVG image');
      expect(type('image/webp'), 'WebP image');
      expect(type('video/mp4'), 'MP4 video');
      expect(type('audio/mpeg'), 'MP3 audio');
      expect(type('text/plain'), 'Text');
      expect(type('text/html'), 'HTML');
      expect(type('application/json'), 'JSON');
      expect(type('application/zip'), 'ZIP archive');
    });

    test('calls an Arweave manifest a deployment', () {
      expect(type('application/x.arweave-manifest+json'), 'Deployment');
    });

    test('ignores parameters and case in the content type', () {
      expect(type('Text/Plain; charset=utf-8'), 'Text');
      expect(type('application/json; charset=utf-8'), 'JSON');
    });

    test('falls back to the extension, uppercased, then to File', () {
      expect(
        type(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'report.docx',
        ),
        'DOCX file',
      );
      expect(type('application/octet-stream', 'archive.bin'), 'BIN file');
      expect(type('', 'notes.md'), 'MD file');
      expect(type('application/octet-stream', 'README'), 'File');
      expect(type('', 'not an extension.with spaces here'), 'File');
    });

    test('an image of a kind with no name here falls back too', () {
      expect(type('image/x-weird', 'a.xyz'), 'XYZ file');
    });
  });

  group('the Status', () {
    test('says Pending, Permanent and Failed, and nothing for no status', () {
      expect(driveTableStatusLabel(l10n, TransactionStatus.pending), 'Pending');
      expect(
        driveTableStatusLabel(l10n, TransactionStatus.confirmed),
        'Permanent',
      );
      expect(driveTableStatusLabel(l10n, TransactionStatus.failed), 'Failed');
      expect(driveTableStatusLabel(l10n, null), isNull);
    });

    test('ranks Failed, Pending, Permanent, then none', () {
      expect(
        [
          null,
          TransactionStatus.confirmed,
          TransactionStatus.pending,
          TransactionStatus.failed,
        ].map(driveTableStatusRank),
        [3, 2, 1, 0],
      );
    });
  });

  group('which columns show', () {
    bool shown(int index, double width, [Map<int, bool> saved = const {}]) =>
        showsAddedColumn(index: index, width: width, columnVisibility: saved);

    // The icon and the name's extension already say what a file is.
    test('Type, Transaction ID and Status are all off by default', () {
      expect(shown(ColumnIndexes.type, 1200), isFalse);
      expect(shown(ColumnIndexes.transactionId, 1200), isFalse);
      expect(shown(ColumnIndexes.status, 1200), isFalse);
    });

    test('all three drop when the layout is narrow, even when chosen', () {
      const chosen = {
        ColumnIndexes.type: true,
        ColumnIndexes.transactionId: true,
        ColumnIndexes.status: true,
      };
      for (final index in [
        ColumnIndexes.type,
        ColumnIndexes.transactionId,
        ColumnIndexes.status,
      ]) {
        expect(shown(index, typeColumnsMinWidth, chosen), isFalse);
        expect(shown(index, typeColumnsMinWidth + 1, chosen), isTrue);
      }
    });

    test('they go before License does as the table narrows', () {
      expect(typeColumnsMinWidth, greaterThan(820));
    });

    test('the reader\'s choice wins', () {
      expect(
          shown(ColumnIndexes.type, 1200, {ColumnIndexes.type: true}), isTrue);
      expect(shown(ColumnIndexes.type, 1200, {ColumnIndexes.type: false}),
          isFalse);
      expect(
        shown(ColumnIndexes.transactionId, 1200,
            {ColumnIndexes.transactionId: true}),
        isTrue,
      );
      expect(
        shown(ColumnIndexes.status, 1200, {ColumnIndexes.status: true}),
        isTrue,
      );
    });

    test('a choice saved before these columns existed means the same columns',
        () {
      // What an existing reader's store holds: the five columns, by number.
      const old = {0: true, 1: true, 2: false, 3: true, 4: true};

      expect(shown(ColumnIndexes.type, 1200, old), isFalse);
      expect(shown(ColumnIndexes.transactionId, 1200, old), isFalse);
      expect(shown(ColumnIndexes.status, 1200, old), isFalse);
    });

    test('the numbers of the first five columns have not moved', () {
      expect(
        [
          ColumnIndexes.name,
          ColumnIndexes.size,
          ColumnIndexes.lastUpdated,
          ColumnIndexes.dateCreated,
          ColumnIndexes.licenseType,
        ],
        [0, 1, 2, 3, 4],
      );
      expect(
        [
          ColumnIndexes.type,
          ColumnIndexes.transactionId,
          ColumnIndexes.status,
          ColumnIndexes.count,
        ],
        [5, 6, 7, 8],
      );
    });
  });

  group('sorting', () {
    final epoch = DateTime(2026, 1, 1);

    FileDataTableItem file(
      String name, {
      String contentType = 'text/plain',
      String? status,
      String? txId,
    }) =>
        FileDataTableItem(
          driveId: 'drive',
          lastUpdated: epoch,
          name: name,
          size: 1,
          dateCreated: epoch,
          contentType: contentType,
          fileStatusFromTransactions: status,
          index: 0,
          isOwner: true,
          fileId: 'file-$name',
          parentFolderId: 'root',
          dataTxId: txId ?? 'tx-$name',
          lastModifiedDate: epoch,
          metadataTx: null,
          dataTx: null,
          pinnedDataOwnerAddress: null,
        );

    FolderDataTableItem folder(String name) => FolderDataTableItem(
          driveId: 'drive',
          folderId: 'folder-$name',
          name: name,
          lastUpdated: epoch,
          dateCreated: epoch,
          contentType: 'folder',
          index: 0,
          isOwner: true,
        );

    String labelOf(ArDriveDataTableItem item) => driveTableTypeLabel(
          l10n,
          driveTableType(contentType: item.contentType, name: item.name),
        );

    /// What the table does with a column: the sort, folders first. `desc` is
    /// the plain order and `asc`, the one the first click gives, its reverse,
    /// as for every other column.
    List<String> sorted(
      List<ArDriveDataTableItem> items,
      int column,
      TableSort order,
    ) {
      final folders = items.whereType<FolderDataTableItem>().toList();
      final files = items.whereType<FileDataTableItem>().toList();
      sortDriveTableItems(folders, files, column, order, typeLabel: labelOf);
      return [...folders, ...files].map((e) => e.name).toList();
    }

    test('by Type, alphabetically by label, folders first', () {
      final items = <ArDriveDataTableItem>[
        file('c', contentType: 'video/mp4'),
        file('a', contentType: 'image/png'),
        folder('z-folder'),
        file('b', contentType: 'application/pdf'),
      ];

      // "MP4 video" < "PDF" < "PNG image", folders ahead of all of them.
      expect(sorted(items, ColumnIndexes.type, TableSort.desc),
          ['z-folder', 'c', 'b', 'a']);
      expect(sorted(items, ColumnIndexes.type, TableSort.asc),
          ['z-folder', 'a', 'b', 'c']);
    });

    test('by Type, files of one type fall back to their names', () {
      final items = <ArDriveDataTableItem>[
        file('b.png', contentType: 'image/png'),
        file('a.png', contentType: 'image/png'),
      ];

      expect(sorted(items, ColumnIndexes.type, TableSort.desc),
          ['a.png', 'b.png']);
    });

    test('by Transaction ID, on the whole ID', () {
      final items = <ArDriveDataTableItem>[
        // The short forms are both "abcdef...wxyz"; only the middle differs.
        file('second', txId: 'abcdef${'b' * 30}wxyz'),
        file('first', txId: 'abcdef${'a' * 30}wxyz'),
        folder('folder'),
      ];

      expect(sorted(items, ColumnIndexes.transactionId, TableSort.desc),
          ['folder', 'first', 'second']);
      expect(sorted(items, ColumnIndexes.transactionId, TableSort.asc),
          ['folder', 'second', 'first']);
    });

    test('by Status: Failed, Pending, Permanent, folders first', () {
      final items = <ArDriveDataTableItem>[
        file('permanent', status: TransactionStatus.confirmed),
        file('failed', status: TransactionStatus.failed),
        folder('folder'),
        file('pending', status: TransactionStatus.pending),
      ];

      expect(sorted(items, ColumnIndexes.status, TableSort.desc),
          ['folder', 'failed', 'pending', 'permanent']);
      expect(sorted(items, ColumnIndexes.status, TableSort.asc),
          ['folder', 'permanent', 'pending', 'failed']);
    });

    test('the other columns still sort as they did', () {
      final items = <ArDriveDataTableItem>[
        file('b'),
        file('a'),
      ];

      expect(sorted(items, ColumnIndexes.name, TableSort.desc), ['a', 'b']);
      expect(sorted(items, ColumnIndexes.name, TableSort.asc), ['b', 'a']);
    });
  });
}
