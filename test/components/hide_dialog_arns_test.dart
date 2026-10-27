import 'dart:async';

import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart' show ArNSNameType;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MockHideBloc extends MockBloc<HideEvent, HideState>
    implements HideBloc {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

class _MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

final _date = DateTime(2026);

FileDataTableItem _file() => FileDataTableItem(
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
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const InitialHideState());
    registerFallbackValue(
        const RefreshOptions(userHasHiddenItems: false) as GlobalHideEvent);
  });

  // Hiding a file takes its row out of the list, and the menu item that
  // started the hide goes with it. The offer to remove the file's name was
  // shown from that item's context, which was gone by then, so it never
  // appeared.
  testWidgets('the name offer shows once the hidden file has left the list',
      (tester) async {
    final config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
    ));
    final names = _MockNamesCubit();
    whenListen(
      names,
      const Stream<ArNSNamesState>.empty(),
      initialState: const ArNSNamesState(
        status: ArNSNamesStatus.loaded,
        names: [
          ArNSManagedName(
            name: 'acme',
            processId: 'ant',
            role: ArNSRole.owner,
            type: ArNSNameType.permabuy,
            endTimestamp: null,
            undernameLimit: 10,
            records: [
              ArNSNameRecord(
                name: 'acme',
                undername: 'blog',
                transactionId: 'tx',
                ttlSeconds: 300,
              ),
            ],
          ),
        ],
      ),
    );
    final hideBloc = _MockHideBloc();
    final hideStates = StreamController<HideState>.broadcast();
    whenListen(
      hideBloc,
      hideStates.stream,
      initialState: const InitialHideState(),
    );
    final globalHide = _MockGlobalHideBloc();
    when(() => globalHide.state)
        .thenReturn(const GlobalHideInitial(userHasHiddenDrive: false));
    final rowShown = ValueNotifier(true);
    final driveDetail = _MockDriveDetailCubit();

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConfigService>.value(value: config),
          ChangeNotifierProvider(create: (_) => ActivityTracker()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ArNSNamesCubit>.value(value: names),
            BlocProvider<HideBloc>.value(value: hideBloc),
            BlocProvider<GlobalHideBloc>.value(value: globalHide),
            BlocProvider<DriveDetailCubit>.value(value: driveDetail),
          ],
          child: ArDriveApp(
            builder: (context) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: rowShown,
                  builder: (context, shown, _) => shown
                      ? Builder(
                          builder: (rowContext) => TextButton(
                            onPressed: () => promptToToggleHideState(
                              rowContext,
                              item: _file(),
                            ),
                            child: const Text('Hide'),
                          ),
                        )
                      : const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Hide'));
    await tester.pump(const Duration(milliseconds: 500));
    // The hide writes the file's new revision before it reports success, and
    // the list drops the hidden row as soon as the database says so.
    rowShown.value = false;
    await tester.pump();
    hideStates.add(const SuccessHideState(hideAction: HideAction.hideFile));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Remove its name too?'), findsOneWidget);
  });
}
