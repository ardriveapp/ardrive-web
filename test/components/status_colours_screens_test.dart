@Tags(['measurement'])
library;

// Screenshots of the status colours, in notices and on real screens, for
// review. Not an assertion: run with
// flutter test test/components/status_colours_screens_test.dart --run-skipped --tags=measurement
// and find the PNGs in build/status-shots.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/gar/presentation/widgets/gateway_input_modal.dart';
import 'package:ardrive/gar/utils/gateway_validator.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _outDir = Directory('build/status-shots');

Future<ByteData> _read(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadFonts() async {
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
  ]) {
    wavehaus.addFont(_read('$dir/$f'));
  }
  await wavehaus.load();
  await (FontLoader('packages/ardrive_ui/ArDriveIcons')
        ..addFont(_read('$dir/ArDriveIcons.ttf')))
      .load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await (FontLoader('MaterialIcons')
        ..addFont(_read(
            '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
  ArDriveMonospace.readFont = () => _read('$dir/mono/RobotoMono-Regular.ttf');
  await ArDriveMonospace.ensureLoaded();
}

UploadPaymentMethodInfo _payment({
  required UploadMethod method,
  required bool arFine,
  required bool creditsFine,
}) {
  UploadCostEstimate cost(int winston) => UploadCostEstimate(
        pstFee: BigInt.zero,
        totalCost: BigInt.from(winston),
        totalSize: 1,
        usdUploadCost: 1,
      );

  return UploadPaymentMethodInfo(
    uploadMethod: method,
    costEstimateTurbo: cost(4100000000),
    costEstimateAr: cost(7935750989),
    hasNoTurboBalance: false,
    isTurboUploadPossible: true,
    arBalance: arFine ? '1.0619' : '0.0012',
    sufficientArBalance: arFine,
    turboCredits: creditsFine ? '2.0370' : '0.0004',
    sufficentCreditsBalance: creditsFine,
    freeStatus: FreeUploadStatus.notEligible,
    totalSize: 1,
  );
}

void main() {
  setUpAll(_loadFonts);

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget Function(BuildContext context) build, {
    required bool phone,
    required bool dark,
    double? height,
    Future<void> Function()? act,
  }) async {
    final size = phone ? Size(390, height ?? 760) : Size(1100, height ?? 680);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ArDriveApp(
          themeData: dark ? null : lightTheme(),
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ArDriveTheme.of(context).themeData.materialThemeData,
            home: Builder(builder: build),
          ),
        ),
      ),
    );
    await tester.pump();
    if (act != null) await act();
    for (var i = 0; i < 3; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${_outDir.path}/$name-${phone ? '390' : 'desktop'}-${dark ? 'dark' : 'light'}.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  /// [child] on a dialog surface over the page.
  Widget dialog(BuildContext context, Widget child, {required bool phone}) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Scaffold(
      backgroundColor: colors.containerL0,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: colors.primitives.transparent900_64),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.all(phone ? 12 : 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget notices(BuildContext context, {required bool phone}) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    Widget column(String label, Color background) => Container(
          width: phone ? double.infinity : 500,
          padding: const EdgeInsets.all(ArDriveSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(ArDriveRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: typography.paragraphSmall(color: colors.textLow)),
              const SizedBox(height: ArDriveSpacing.sm),
              const ArDriveNotice(
                type: ArDriveNoticeType.info,
                message: 'Your drive is syncing. New files appear as they '
                    'arrive.',
              ),
              const SizedBox(height: ArDriveSpacing.sm),
              const ArDriveNotice(
                type: ArDriveNoticeType.warning,
                title: 'Anyone with the link can see this file',
                message: 'Sharing a public file cannot be undone.',
              ),
              const SizedBox(height: ArDriveSpacing.sm),
              ArDriveNotice(
                type: ArDriveNoticeType.error,
                message: 'Not enough Turbo Credits or AR to upload.',
                actionLabel: 'Add credits',
                onAction: () {},
              ),
              const SizedBox(height: ArDriveSpacing.sm),
              const ArDriveNotice(
                type: ArDriveNoticeType.success,
                message: 'Gateway is active and ready.',
              ),
              const SizedBox(height: ArDriveSpacing.md),
              Row(
                children: [
                  for (final (status, label) in [
                    (TransactionStatus.pending, 'Pending'),
                    (TransactionStatus.confirmed, 'Confirmed'),
                    (TransactionStatus.failed, 'Failed'),
                  ]) ...[
                    FileStatusDot(status: status),
                    const SizedBox(width: ArDriveSpacing.xs),
                    Text(label,
                        style:
                            typography.paragraphSmall(color: colors.textMid)),
                    const SizedBox(width: ArDriveSpacing.md),
                  ],
                ],
              ),
            ],
          ),
        );

    final page = column('On the page', colors.containerL0);
    final card = column('On a dialog', colors.containerL3);
    return Scaffold(
      backgroundColor: colors.containerL0,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ArDriveSpacing.md),
        child: phone
            ? Column(children: [page, const SizedBox(height: 12), card])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [page, const SizedBox(width: 24), card],
              ),
      ),
    );
  }

  Widget gateway(GatewayValidationResult result) => GatewayInputModal(
        initialGateway: 'https://turbo-gateway.com',
        onSave: (_) {},
        validate: (_) async => result,
      );

  Future<void> Function() typeGateway(WidgetTester tester) => () async {
        await tester.enterText(
            find.byType(TextFormField), 'https://my-gateway.example');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
      };

  Widget payment(
    BuildContext context,
    UploadPaymentMethodInfo info, {
    required bool phone,
  }) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return dialog(
      context,
      Container(
        width: phone ? double.infinity : 560,
        padding: const EdgeInsets.all(ArDriveSpacing.lg),
        decoration: BoxDecoration(
          color: colors.containerL3,
          borderRadius: BorderRadius.circular(ArDriveRadius.lg),
        ),
        child: SingleChildScrollView(
          child: PaymentMethodSelector(
            uploadMethodInfo: info,
            onTurboTopupSucess: () {},
            onArSelect: () {},
            onTurboSelect: () {},
          ),
        ),
      ),
      phone: phone,
    );
  }

  for (final dark in [false, true]) {
    for (final phone in [false, true]) {
      final suffix =
          '${phone ? 'phone' : 'desktop'} ${dark ? 'dark' : 'light'}';

      testWidgets('notices, $suffix', (tester) async {
        await capture(
          tester,
          'notices',
          (context) => notices(context, phone: phone),
          phone: phone,
          dark: dark,
          height: phone ? 1000 : null,
        );
      });

      testWidgets('gateway warning, $suffix', (tester) async {
        await capture(
          tester,
          'gateway-warning',
          (context) => dialog(
            context,
            gateway(const GatewayValidationResult(
              isValid: true,
              isActive: true,
              isArweaveGateway: false,
              message: 'Gateway is active but may not be an Arweave gateway.',
            )),
            phone: phone,
          ),
          phone: phone,
          dark: dark,
          act: typeGateway(tester),
        );
      });

      testWidgets('gateway error, $suffix', (tester) async {
        await capture(
          tester,
          'gateway-error',
          (context) => dialog(
            context,
            gateway(const GatewayValidationResult(
              isValid: true,
              isActive: false,
              isArweaveGateway: false,
              message: 'Gateway is not responding. Please check the URL.',
            )),
            phone: phone,
          ),
          phone: phone,
          dark: dark,
          act: typeGateway(tester),
        );
      });

      testWidgets('payment warning, $suffix', (tester) async {
        await capture(
          tester,
          'payment-warning',
          (context) => payment(
            context,
            _payment(method: UploadMethod.ar, arFine: true, creditsFine: true),
            phone: phone,
          ),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('payment error, $suffix', (tester) async {
        await capture(
          tester,
          'payment-error',
          (context) => payment(
            context,
            _payment(
                method: UploadMethod.turbo, arFine: false, creditsFine: false),
            phone: phone,
          ),
          phone: phone,
          dark: dark,
        );
      });
    }
  }
}
