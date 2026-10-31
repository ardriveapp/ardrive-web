import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/item_menus.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

/// Each kind of item has one menu, built by item_menus.dart for every
/// surface, in the 27 October design's order, with a divider between groups
/// (#2370). These pin that order, and what an unsynced drive leaves out.
void main() {
  late MockProfileCubit profileCubit;

  setUp(() {
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state)
        .thenReturn(ProfileLoggedIn(user: getTestUser(), useTurbo: false));
  });

  Drive drive({String privacy = 'public'}) => Drive(
        id: 'drive-a',
        rootFolderId: 'drive-a-root',
        ownerAddress: 'owner',
        name: 'Photos',
        privacy: privacy,
        isHidden: false,
        dateCreated: DateTime(2026, 3, 4),
        lastUpdated: DateTime(2026, 3, 4),
      );

  FolderDataTableItem folder({bool isOwner = true}) => FolderDataTableItem(
        driveId: 'drive-a',
        folderId: 'folder-a',
        name: 'Trips',
        lastUpdated: DateTime(2026, 3, 4),
        dateCreated: DateTime(2026, 3, 4),
        contentType: 'folder',
        index: 0,
        isOwner: isOwner,
      );

  FileDataTableItem file({
    bool isOwner = true,
    String contentType = 'image/png',
    String? status,
  }) =>
      FileDataTableItem(
        driveId: 'drive-a',
        fileId: 'file-a',
        parentFolderId: 'folder-a',
        name: 'beach.png',
        size: 10,
        lastUpdated: DateTime(2026, 3, 4),
        dateCreated: DateTime(2026, 3, 4),
        lastModifiedDate: DateTime(2026, 3, 4),
        contentType: contentType,
        index: 0,
        isOwner: isOwner,
        dataTxId: 'data-tx',
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
        fileStatusFromTransactions: status,
      );

  /// The menu's labels, a divider as '|'.
  Future<List<String>> labels(
    WidgetTester tester,
    List<ArDriveDropdownItem> Function(BuildContext context) build,
  ) async {
    late List<ArDriveDropdownItem> items;
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<ProfileCubit>.value(
            value: profileCubit,
            child: Builder(builder: (context) {
              items = build(context);
              return const SizedBox();
            }),
          ),
        ),
      ),
    );
    return [
      for (final item in items)
        item.isDivider ? '|' : (item.content as ArDriveDropdownItemTile).name,
    ];
  }

  group('a drive', () {
    testWidgets('you own, synced', (tester) async {
      expect(
        await labels(
          tester,
          (context) => driveMenuItems(
            context,
            drive: drive(),
            isOwner: true,
            isSynced: true,
            isSyncing: false,
            onMoreInfo: () {},
          ),
        ),
        [
          'Share drive',
          '|',
          'Download',
          'Export contents',
          '|',
          'Rename drive',
          'Create snapshot',
          'Hide',
          '|',
          'Sync this drive',
          'Full resync this drive',
          '|',
          'More info',
        ],
      );
    });

    // #18: Export read as a second Download, with the same arrow.
    testWidgets('Export contents has its own icon, not Download\'s',
        (tester) async {
      late List<ArDriveDropdownItem> items;
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BlocProvider<ProfileCubit>.value(
              value: profileCubit,
              child: Builder(builder: (context) {
                items = driveMenuItems(
                  context,
                  drive: drive(),
                  isOwner: true,
                  isSynced: true,
                  isSyncing: false,
                  onMoreInfo: () {},
                );
                return const SizedBox();
              }),
            ),
          ),
        ),
      );
      IconData iconOf(String name) => (items
              .where((item) => !item.isDivider)
              .map((item) => item.content as ArDriveDropdownItemTile)
              .firstWhere((tile) => tile.name == name)
              .icon as ArDriveIcon)
          .icon;

      expect(iconOf('Export contents'), isNot(iconOf('Download')));
      expect(iconOf('Export contents'), ArDriveIcons.table().icon);
    });

    testWidgets('shared with you: no owner actions, Detach last',
        (tester) async {
      expect(
        await labels(
          tester,
          (context) => driveMenuItems(
            context,
            drive: drive(),
            isOwner: false,
            isSynced: true,
            isSyncing: false,
            onMoreInfo: () {},
          ),
        ),
        [
          'Share drive',
          '|',
          'Download',
          'Export contents',
          '|',
          'Sync this drive',
          'Full resync this drive',
          '|',
          'More info',
          '|',
          'Detach drive',
        ],
      );
    });

    testWidgets('not synced on this device: nothing that reads its contents',
        (tester) async {
      expect(
        await labels(
          tester,
          (context) => driveMenuItems(
            context,
            drive: drive(),
            isOwner: true,
            isSynced: false,
            isSyncing: false,
            onMoreInfo: () {},
          ),
        ),
        ['Share drive', '|', 'Hide', '|', 'Sync this drive', '|', 'More info'],
      );
    });

    testWidgets('in its own details: no More info, no trailing divider',
        (tester) async {
      final items = await labels(
        tester,
        (context) => driveMenuItems(
          context,
          drive: drive(),
          isOwner: true,
          isSynced: true,
          isSyncing: false,
          onMoreInfo: null,
        ),
      );
      expect(items, isNot(contains('More info')));
      expect(items.last, 'Full resync this drive');
    });
  });

  testWidgets('a folder you own', (tester) async {
    expect(
      await labels(
        tester,
        (context) => folderMenuItems(
          context,
          folder: folder(),
          drive: drive(),
          zipName: () => 'Trips',
          onMoreInfo: () {},
        ),
      ),
      [
        'Open',
        '|',
        'Share folder',
        '|',
        'Download',
        '|',
        'Rename',
        'Move',
        'Add license',
        'Hide',
        '|',
        'More info',
      ],
    );
  });

  testWidgets('a folder you do not own: open, share, download, info',
      (tester) async {
    expect(
      await labels(
        tester,
        (context) => folderMenuItems(
          context,
          folder: folder(isOwner: false),
          drive: drive(),
          zipName: () => 'Trips',
          onMoreInfo: () {},
        ),
      ),
      ['Open', '|', 'Share folder', '|', 'Download', '|', 'More info'],
    );
  });

  group('a file', () {
    testWidgets('you own, in a public drive', (tester) async {
      expect(
        await labels(
          tester,
          (context) => fileMenuItems(
            context,
            file: file(),
            drive: drive(),
            onMoreInfo: () {},
          ),
        ),
        [
          'Preview',
          '|',
          'Share file',
          '|',
          'Download',
          '|',
          'Rename',
          'Move',
          'Add license',
          'Hide',
          '|',
          'More info',
        ],
      );
    });

    testWidgets('a note is edited, not renamed', (tester) async {
      final items = await labels(
        tester,
        (context) => fileMenuItems(
          context,
          file: file(contentType: 'text/markdown'),
          drive: drive(),
          onMoreInfo: () {},
        ),
      );
      expect(items, contains('Edit note'));
      expect(items, isNot(contains('Rename')));
    });

    testWidgets('in a private drive: no preview', (tester) async {
      final items = await labels(
        tester,
        (context) => fileMenuItems(
          context,
          file: file(),
          drive: drive(privacy: 'private'),
          onMoreInfo: () {},
        ),
      );
      expect(items.first, 'Share file');
    });

    testWidgets('still uploading: the status check sits by More info',
        (tester) async {
      final items = await labels(
        tester,
        (context) => fileMenuItems(
          context,
          file: file(status: TransactionStatus.pending),
          drive: drive(),
          onMoreInfo: () {},
        ),
      );
      expect(items.sublist(items.length - 2),
          ['Check upload status', 'More info']);
    });
  });
}
