import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

/// A publication root on a phone: its header is the first thing in the list's
/// scroll, and goes up with the rows under the finger.
void main() {
  final drive = Drive(
    id: 'drive',
    rootFolderId: 'root',
    name: 'Drive',
    ownerAddress: 'owner',
    dateCreated: DateTime(2026, 1, 1),
    lastUpdated: DateTime(2026, 1, 1),
    privacy: 'public',
    isHidden: false,
  );

  FileDataTableItem file(String name) => FileDataTableItem(
        driveId: 'drive',
        lastUpdated: DateTime(2026, 1, 1),
        name: name,
        size: 10,
        dateCreated: DateTime(2026, 1, 1),
        contentType: 'text/markdown',
        index: 0,
        isOwner: true,
        fileId: 'file-$name',
        parentFolderId: 'root',
        dataTxId: 'tx-$name',
        lastModifiedDate: DateTime(2026, 1, 1),
        metadataTx: null,
        dataTx: null,
        pinnedDataOwnerAddress: null,
      );

  final notes = file('notes.md');

  late MockDriveDetailCubit cubit;
  final extent = CollapsingHeaderExtent();
  const coverKey = Key('cover');

  setUpAll(() => registerFallbackValue(notes));

  setUp(() {
    cubit = MockDriveDetailCubit();
    when(() => cubit.selectedItem).thenReturn(null);
    when(() => cubit.selectDataItem(any())).thenAnswer((_) async {});
  });

  Future<ScrollController> pump(
    WidgetTester tester,
    ArDriveThemeData theme, {
    required int count,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final items = <ArDriveDataTableItem>[
      for (var i = 0; i < count; i++) file('file $i.md'),
    ];
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: theme,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: BlocProvider<DriveDetailCubit>.value(
            value: cubit,
            child: Scaffold(
              body: ArDriveItemList(
                controller: controller,
                items: items,
                drive: drive,
                leadingExtent: extent,
                pinnedInset: 56,
                leadingSlivers: [
                  SliverCollapsingHeader(
                    barHeight: 56,
                    extent: extent,
                    header: const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SizedBox(key: coverKey, height: 300),
                    ),
                    bar: const ColoredBox(
                      color: Colors.white,
                      child: Text('Bar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  for (final (name, count) in [('a short list', 9), ('a long list', 80)]) {
    testWidgets('a finger drag moves the header with it, $name',
        (tester) async {
      final controller = await pump(tester, lightTheme(), count: count);
      final top = tester.getTopLeft(find.byKey(coverKey)).dy;

      // One finger, kept down: it has to cross the touch slop before the
      // list takes the drag, so the first moves scroll nothing. Then every
      // step moves the header with it.
      var previous = top;
      var moved = 0;
      final gesture = await tester.startGesture(const Offset(200, 500));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(0, -6));
        await tester.pump(const Duration(milliseconds: 16));
        final offset = controller.offset;
        final now = tester.getTopLeft(find.byKey(coverKey)).dy;
        expect(now, moreOrLessEquals(top - offset, epsilon: 0.5));
        expect(now, lessThanOrEqualTo(previous));
        if (offset > 0) moved++;
        previous = now;
      }
      // It did scroll: the checks above are about a header that moved.
      expect(controller.offset, greaterThan(100));
      expect(moved, greaterThan(20));
      expect(previous, lessThan(top - 100));
      await gesture.up();
      await tester.pumpAndSettle();
      // The short list scrolls exactly as far as the header collapses.
      if (count == 9) {
        expect(controller.position.maxScrollExtent,
            moreOrLessEquals(extent.value - 56, epsilon: 0.01));
      }

      // Back down, to everything shown.
      await tester.fling(
          find.byType(ArDriveItemList), const Offset(0, 2000), 3000);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(tester.getTopLeft(find.byKey(coverKey)).dy, top);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a row under the bar is still reachable below it',
      (tester) async {
    final controller = await pump(tester, lightTheme(), count: 9);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    // The first row is just under the bar, and can be tapped there.
    await tester.tap(find.text('file 0.md'));
    verify(() => cubit.selectDataItem(any())).called(1);
  });
}
