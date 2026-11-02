import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/publication/presentation/publication_loader_page.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockLoader extends MockCubit<PublicationLoaderState>
    implements PublicationLoaderCubit {}

const _owner = 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA';

PublicationConfig _config({
  String? cover = 'cover.jpg',
  String? icon = 'icon-512.png',
  String? ownerName = 'Matt Johnson',
}) =>
    PublicationConfig(
      version: 1,
      driveId: 'c863be1f-a725-4554-9a9e-18268ed8a035',
      rootFolderId: '41520b33-28c1-4892-886b-b845a5709085',
      scope: const PublicationDriveScope(),
      privacy: 'public',
      owner: _owner,
      ownerName: ownerName,
      snapshot:
          const PublicationSnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'Field recordings',
      description: 'Rain, trains and rooms.',
      images: PublicationImages(cover: cover, icon: icon),
      publishedAt: null,
      viewer: null,
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Size size,
    PublicationConfig? config,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loader = _MockLoader();
    whenListen(
      loader,
      const Stream<PublicationLoaderState>.empty(),
      initialState: PublicationReady(
        config ?? _config(),
        stats: const PublicationStats(fileCount: 79, totalSize: 320794),
        ownerVerified: true,
      ),
    );
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlocProvider<PublicationLoaderCubit>.value(
                value: loader,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    // Network images fail in tests, which leaves the placeholders.
    await tester.pump();
    await tester.pump();
  }

  Widget header({bool collapsed = false, bool compact = false}) =>
      PublicationHeader(
        coverHeight: compact ? 120 : 200,
        collapsed: collapsed,
        compact: compact,
        onDownload: () {},
        downloadsSelection: false,
        onCopyLink: () {},
      );

  /// The cover's placeholder (no size of its own) and the icon's (square).
  Finder cover() => find.byWidgetPredicate(
      (w) => w is PublicationImagePlaceholder && w.width == null);
  Finder icon() => find.byWidgetPredicate(
      (w) => w is PublicationImagePlaceholder && w.width != null);

  for (final (name, size, compact, iconSize) in [
    ('on a wide screen', const Size(1400, 900), false, 88.0),
    ('on a phone', const Size(390, 844), true, 64.0),
  ]) {
    group('the header $name', () {
      testWidgets('cuts the icon into the cover edge, inset from its left',
          (tester) async {
        await pump(tester, header(compact: compact), size: size);

        final coverRect = tester.getRect(cover());
        final iconRect = tester.getRect(icon());
        expect(iconRect.size, Size.square(iconSize));
        // Centred on the cover's bottom edge: half on it, half below.
        expect(iconRect.top, lessThan(coverRect.bottom));
        expect(iconRect.bottom, greaterThan(coverRect.bottom));
        expect(
          coverRect.bottom - iconRect.top,
          moreOrLessEquals(iconSize / 2),
        );
        expect(iconRect.left - coverRect.left, compact ? 12 + 4 : 16 + 4);
      });

      testWidgets('starts the title ${compact ? 'below' : 'right of'} the icon',
          (tester) async {
        await pump(tester, header(compact: compact), size: size);

        final iconRect = tester.getRect(icon());
        final coverRect = tester.getRect(cover());
        final title = tester.getRect(find.text('Field recordings'));
        if (compact) {
          expect(title.top, greaterThanOrEqualTo(iconRect.bottom));
        } else {
          expect(title.left, greaterThanOrEqualTo(iconRect.right + 4 + 16));
          // A little below the cover's bottom edge, beside the icon.
          expect(title.top, greaterThan(coverRect.bottom));
          expect(title.top, lessThan(iconRect.bottom));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('has no cover and no icon once collapsed', (tester) async {
        await pump(tester, header(collapsed: true, compact: compact),
            size: size);

        expect(cover(), findsNothing);
        expect(icon(), findsNothing);
        expect(find.text('Field recordings'), findsOneWidget);
        expect(find.text('Rain, trains and rooms.'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('with a cover and no icon is cover, then title',
          (tester) async {
        final config = _config(icon: null);
        await pump(tester, header(compact: compact),
            size: size, config: config);

        expect(icon(), findsNothing);
        final title = tester.getRect(find.text('Field recordings'));
        expect(title.top, greaterThanOrEqualTo(tester.getRect(cover()).bottom));
        expect(title.left, tester.getRect(cover()).left);
      });

      testWidgets('with an icon and no cover puts the icon left of the title',
          (tester) async {
        final config = _config(cover: null);
        await pump(tester, header(compact: compact),
            size: size, config: config);

        expect(cover(), findsNothing);
        final iconRect = tester.getRect(icon());
        expect(iconRect.size, Size.square(compact ? 48 : 56));
        final title = tester.getRect(find.text('Field recordings'));
        expect(title.left, greaterThanOrEqualTo(iconRect.right));
        expect(title.top, lessThan(iconRect.bottom));
        expect(tester.takeException(), isNull);
      });

      testWidgets('does not overflow with a long title and name',
          (tester) async {
        final config = _config(ownerName: 'A very long publisher name ' * 4);
        await pump(tester, header(compact: compact),
            size: size, config: config);

        expect(tester.takeException(), isNull);
      });
    });
  }

  group('the file page head', () {
    testWidgets('overlaps the icon on the cover on a wide screen',
        (tester) async {
      await pump(tester, PublicationFileHead(config: _config()),
          size: const Size(1400, 900));

      final coverRect = tester.getRect(cover());
      final iconRect = tester.getRect(icon());
      expect(iconRect.size, const Size.square(88));
      expect(iconRect.top, lessThan(coverRect.bottom));
      expect(iconRect.bottom, greaterThan(coverRect.bottom));
      expect(tester.getRect(find.text('Field recordings')).left,
          greaterThanOrEqualTo(iconRect.right + 4 + 16));
      expect(tester.takeException(), isNull);
    });

    testWidgets('puts the title below the icon on a phone', (tester) async {
      await pump(tester, PublicationFileHead(config: _config()),
          size: const Size(390, 844));

      final iconRect = tester.getRect(icon());
      expect(iconRect.size, const Size.square(64));
      expect(tester.getRect(find.text('Field recordings')).top,
          greaterThanOrEqualTo(iconRect.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  group('the byline', () {
    testWidgets('puts a wallet icon between the name and the address',
        (tester) async {
      await pump(tester, header(), size: const Size(1400, 900));

      final wallet = find.byIcon(Icons.account_balance_wallet_outlined);
      expect(wallet, findsOneWidget);
      final name = tester.getRect(find.text('By Matt Johnson'));
      final address = tester.getRect(find.text(shortenId(_owner)));
      final walletRect = tester.getRect(wallet);
      expect(walletRect.left, greaterThanOrEqualTo(name.right));
      expect(address.left, greaterThanOrEqualTo(walletRect.right));
    });

    testWidgets('sets the address in the lighter monospace style',
        (tester) async {
      await pump(tester, header(), size: const Size(1400, 900));

      final colors = lightTheme().colorTokens;
      final address = tester.widget<Text>(find
          .byWidgetPredicate((w) => w is Text && w.data == shortenId(_owner)));
      expect(address.style!.color, colors.textLow);
      expect(address.style!.fontFamily, ArDriveMonospace.family);
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.account_balance_wallet_outlined))
            .color,
        colors.textLow,
      );
    });

    testWidgets('is "By", the icon and the address without a name',
        (tester) async {
      await pump(tester, header(),
          size: const Size(1400, 900), config: _config(ownerName: null));

      expect(find.text('By'), findsOneWidget);
      expect(
          find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
      expect(find.text(shortenId(_owner)), findsOneWidget);
    });

    testWidgets('names the whole address in a tooltip', (tester) async {
      await pump(tester, header(), size: const Size(1400, 900));

      expect(find.byTooltip(_owner), findsOneWidget);
    });
  });
}
