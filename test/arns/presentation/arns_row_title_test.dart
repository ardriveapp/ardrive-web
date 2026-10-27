import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart' show createMockFileDataTableItem;

class _MockConfigService extends Mock implements ConfigService {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

const _tx = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';

/// An explorer row's name cell with a named file: the file name comes
/// first. With the details panel open the name column narrows, and the
/// chip kept its width while the file name was cut to "e2e-name-1.t…".
void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    final config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
    ));
    final names = _MockNamesCubit();
    whenListen(names, const Stream<ArNSNamesState>.empty(),
        initialState: const ArNSNamesState(
          status: ArNSNamesStatus.loaded,
          address: 'sol',
          names: [
            ArNSManagedName(
              name: 'acme-website',
              processId: 'ant',
              role: ArNSRole.owner,
              type: ArNSNameType.permabuy,
              endTimestamp: null,
              undernameLimit: 10,
              records: [
                ArNSNameRecord(
                  name: 'acme-website',
                  undername: '@',
                  transactionId: _tx,
                  ttlSeconds: 300,
                ),
              ],
            ),
          ],
        ));
    final tile = DriveExplorerItemTile(
      name: 'a.txt',
      size: '1 KB',
      lastUpdated: DateTime(2026, 10, 26),
      dateCreated: DateTime(2026, 10, 26),
      license: '',
      onPressed: () {},
      isHidden: false,
      typography: ArDriveTypographyNew.desktop,
      dataTableItem: createMockFileDataTableItem(name: 'a.txt', dataTxId: _tx),
      colorTokens: ArDriveColorTokens.lightMode(),
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [RepositoryProvider<ConfigService>.value(value: config)],
        child: BlocProvider<ArNSNamesCubit>.value(
          value: names,
          child: ArDriveApp(
            builder: (context) => MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: width, child: tile.row.first),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  RenderParagraph title(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(find.text('a.txt'));

  testWidgets('a narrow column keeps the whole file name', (tester) async {
    await pump(tester, 150);

    expect(title(tester).didExceedMaxLines, isFalse);
  });

  testWidgets('a wide column shows the name beside it', (tester) async {
    await pump(tester, 600);

    expect(title(tester).didExceedMaxLines, isFalse);
    expect(find.text('acme-website.ar.io'), findsOneWidget);
  });
}
