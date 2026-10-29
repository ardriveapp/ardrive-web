import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_utils/mocks.dart';

/// The details panel's menu (EntityActionsMenu) used to size itself as one
/// row per item. Since the menus have dividers between their groups, that
/// left a row's worth of empty card under the last item for each divider.
void main() {
  testWidgets('the details menu is as tall as its rows and dividers',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final syncCubit = MockSyncBloc();
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());

    final drive = Drive(
      id: 'drive-a',
      rootFolderId: 'drive-a-root',
      ownerAddress: 'owner',
      name: 'Photos',
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime(2026, 3, 4),
      lastUpdated: DateTime(2026, 3, 4),
    );
    final folder = FolderDataTableItem(
      driveId: 'drive-a',
      folderId: 'folder-a',
      name: 'Trips',
      lastUpdated: DateTime(2026, 3, 4),
      dateCreated: DateTime(2026, 3, 4),
      contentType: 'folder',
      index: 0,
      isOwner: true,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BlocProvider<SyncCubit>.value(
              value: syncCubit,
              child: Align(
                alignment: Alignment.topLeft,
                child: EntityActionsMenu(
                  item: folder,
                  drive: drive,
                  withInfo: false,
                  alignment: const Aligned(
                    follower: Alignment.topLeft,
                    target: Alignment.bottomLeft,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EntityActionsMenu));
    await tester.pumpAndSettle();

    final menu = tester.widget<ArDriveDropdown>(find.byType(ArDriveDropdown));
    final dividers = menu.items.where((item) => item.isDivider).length;
    final rows = menu.items.length - dividers;
    expect(dividers, greaterThan(0), reason: 'the folder menu has groups');

    final card = tester.getRect(find
        .descendant(
          of: find.byType(Overlay),
          matching: find.byType(ArDriveCard),
        )
        .last);
    expect(
      card.height,
      rows * menu.height + dividers * ArDriveDropdownItem.dividerHeight,
    );
  });
}
