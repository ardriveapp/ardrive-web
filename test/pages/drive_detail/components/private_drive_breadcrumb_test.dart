import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/private_drive_marks.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../test_utils/utils.dart';

/// The explorer looked the same inside a private drive as inside a public
/// one: the drives list and the sidebar said which was which, and the page
/// you are actually working in did not.
void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit detailCubit;

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

  Future<void> pump(WidgetTester tester, Size size, Widget child) async {
    await tester.binding.setSurfaceSize(size);
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
              child: Portal(child: Scaffold(body: child)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final lock = find.byType(PrivateDriveLock);

  group('desktop breadcrumb', () {
    const wide = Size(1200, 800);

    Widget trail({required bool isPrivate, int depth = 0}) =>
        DriveDetailBreadcrumbRow(
          rootFolderId: 'root',
          driveName: 'Photos',
          isPrivate: isPrivate,
          path: [
            for (var i = 0; i < depth; i++)
              BreadCrumbRowInfo(text: 'folder $i', targetId: 'f$i'),
          ],
        );

    testWidgets('marks a private drive, with a label a screen reader reads',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, wide, trail(isPrivate: true));

      expect(lock, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Private drive')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('and keeps the mark when the trail collapses', (tester) async {
      await pump(tester, wide, trail(isPrivate: true, depth: 6));

      expect(lock, findsOneWidget);
    });

    testWidgets('and leaves a public drive unmarked', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, wide, trail(isPrivate: false));

      expect(lock, findsNothing);
      expect(find.bySemanticsLabel(RegExp('Private drive')), findsNothing);
      semantics.dispose();
    });
  });

  group('phone folder bar', () {
    const phone = Size(360, 640);

    Widget bar({required bool isPrivate, bool inFolder = false}) =>
        MobileFolderNavigation(
          driveName: 'Photos',
          isShowingHiddenFiles: false,
          isPrivate: isPrivate,
          path: [
            if (inFolder) BreadCrumbRowInfo(text: 'Trips', targetId: 'f1'),
          ],
        );

    testWidgets('marks a private drive at its root', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, phone, bar(isPrivate: true));

      expect(lock, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Private drive')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('and inside a folder, where the drive name is not shown',
        (tester) async {
      await pump(tester, phone, bar(isPrivate: true, inFolder: true));

      expect(lock, findsOneWidget);
    });

    testWidgets('and leaves a public drive unmarked', (tester) async {
      await pump(tester, phone, bar(isPrivate: false));

      expect(lock, findsNothing);
    });

    testWidgets('keeps a long name to one line, which the bar has room for',
        (tester) async {
      const name = 'A publication title long enough to need a second line here';
      await pump(
        tester,
        phone,
        const MobileFolderNavigation(
          driveName: name,
          isShowingHiddenFiles: false,
          isPrivate: false,
          path: [],
        ),
      );

      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.widget<Text>(find.text(name)).maxLines, 1);
    });
  });
}
