import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../test_utils/utils.dart';

/// The header kept up while a drive's root is waited for is the loaded root's
/// header: the same crumb in the same place, never another.
void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit detailCubit;

  final drive = Drive(
    id: 'drive',
    rootFolderId: 'root',
    name: 'Demo Drive',
    ownerAddress: 'owner',
    dateCreated: DateTime(2026, 1, 1),
    lastUpdated: DateTime(2026, 1, 1),
    privacy: 'public',
    isHidden: false,
  );

  setUp(() {
    profileCubit = MockProfileCubit();
    detailCubit = MockDriveDetailCubit();
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: getTestUser(), useTurbo: false),
    );
    whenListen(
      detailCubit,
      const Stream<DriveDetailState>.empty(),
      initialState: DriveDetailLoadInProgress(),
    );
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
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
          home: MultiProvider(
            providers: [
              ListenableProvider<AppRouterDelegate>.value(
                value: AppRouterDelegate(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<DriveDetailCubit>.value(value: detailCubit),
              ],
              child: Portal(
                child: Scaffold(
                  body: Align(alignment: Alignment.topLeft, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The loaded root's header, as the explorer builds it: its card, and the
  /// crumb with the trail the cubit gives a drive's root, which is empty.
  Widget loadedRootHeader() => SizedBox(
        width: 1000,
        child: ArDriveCard(
          backgroundColor: lightTheme().tableTheme.backgroundColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          content: Row(
            children: [
              DriveDetailBreadcrumbRow(
                rootFolderId: drive.rootFolderId,
                path: const [],
                driveName: drive.name,
                isPrivate: false,
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ArDriveClickArea(
                  child: HoverWidget(child: ArDriveIcons.kebabMenu()),
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('says the drive once, where the loaded header does',
      (tester) async {
    await pump(tester, loadedRootHeader());
    final loadedName = tester.getTopLeft(find.text('Demo Drive'));
    final loadedCard = tester.getRect(find.byType(ArDriveCard));
    final loadedHome = tester.getTopLeft(find.byIcon(Icons.home_outlined));

    await pump(
      tester,
      SizedBox(width: 1000, child: ExplorerWaitingHeader(drive: drive)),
    );

    // One crumb for the drive, and no other: never "Demo Drive / Demo Drive".
    expect(find.text('Demo Drive'), findsOneWidget);
    expect(find.text('/'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Demo Drive')), loadedName);
    expect(tester.getTopLeft(find.byIcon(Icons.home_outlined)), loadedHome);
    expect(tester.getRect(find.byType(ArDriveCard)).top, loadedCard.top);
    expect(tester.getRect(find.byType(ArDriveCard)).left, loadedCard.left);
    // Tall enough that the loaded header, with its menu, does not change it.
    expect(tester.getSize(find.byType(ArDriveCard)).height, loadedCard.height);
  });
}
