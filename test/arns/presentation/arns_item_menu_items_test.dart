import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart' show ArDriveDropdownItem;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

final _date = DateTime(2026);

void main() {
  // The name items used a 24 px icon where every other menu item uses
  // defaultIconSize, so Add name sat 4 px right of the items around it.
  testWidgets('the name items use the menu icon size', (tester) async {
    final config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
    ));
    final names = _MockNamesCubit();
    whenListen(names, const Stream<ArNSNamesState>.empty(),
        initialState: const ArNSNamesState(status: ArNSNamesStatus.loaded));

    late List<ArDriveDropdownItem> items;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepositoryProvider<ConfigService>.value(
        value: config,
        child: BlocProvider<ArNSNamesCubit>.value(
          value: names,
          child: Builder(builder: (context) {
            items = arnsItemMenuItems(
              context,
              item: FileDataTableItem(
                driveId: 'drive',
                lastUpdated: _date,
                name: 'a.txt',
                size: 1,
                dateCreated: _date,
                contentType: 'text/plain',
                index: 0,
                isOwner: true,
                fileId: 'file',
                parentFolderId: 'root',
                dataTxId: 'tx',
                lastModifiedDate: _date,
                metadataTx: null,
                dataTx: null,
                pinnedDataOwnerAddress: null,
              ),
              drive: Drive(
                id: 'drive',
                rootFolderId: 'root',
                ownerAddress: 'owner',
                name: 'A public drive',
                privacy: 'public',
                lastBlockHeight: 0,
                isHidden: false,
                dateCreated: _date,
                lastUpdated: _date,
              ),
            );
            return const SizedBox();
          }),
        ),
      ),
    ));

    expect(items, hasLength(1));
    final tile = items.single.content as ArDriveDropdownItemTile;
    expect(tile.icon?.size, defaultIconSize);
  });
}
