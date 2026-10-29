import 'dart:math';

import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One file on the upload review.
typedef UploadReviewFile = ({String name, int size, String contentType});

/// The amounts offered on the Add Turbo Credits step, in US dollars.
const addCreditsPresetsUsd = [10, 25, 50, 100];

/// How the upload review buys Turbo Credits: what an amount buys, paying for
/// it by card, and waiting for the credits to arrive.
abstract class UploadCreditsFunding {
  /// The Turbo Credits [amountUsd] buys, in winston credits, live from Turbo.
  Future<BigInt> creditsFor(int amountUsd);

  /// Pays [amountUsd] by card. The credits bought, or null when the payment
  /// was cancelled or did not go through.
  Future<BigInt?> payByCard(int amountUsd);

  /// Completes once the balance is above [balance], or after a while if it
  /// never gets there: the review reads it again either way.
  Future<void> awaitCredits({required BigInt above});

  /// Reads the price and the balance again.
  void refresh();
}

/// The upload review: the files, what they cost, and the one way forward.
///
/// It never offers Upload unless the upload is free or paid for (see
/// [UploadReviewSummary]). When Turbo Credits are short it offers Add credits,
/// which picks an amount here and pays by card, then comes back to the review.
class UploadReviewDialog extends StatefulWidget {
  const UploadReviewDialog({
    super.key,
    required this.title,
    required this.destination,
    required this.files,
    required this.summary,
    required this.primaryLabel,
    required this.onUpload,
    required this.onCancel,
    required this.funding,
    this.primaryEnabled = true,
    this.paymentChoice,
    this.sourceWalletNotice,
    this.extras = const [],
  });

  final String title;

  /// Where the files go, such as "To My files, private".
  final String destination;
  final List<UploadReviewFile> files;

  /// Null while the price is being read.
  final UploadReviewSummary? summary;

  /// Upload, or the step options lead to first, such as Configure.
  final String primaryLabel;

  /// Other things that hold Upload back, such as a name being priced.
  final bool primaryEnabled;
  final VoidCallback onUpload;
  final VoidCallback onCancel;
  final UploadCreditsFunding funding;

  /// The wallet-or-credits choice, shown when the summary offers one.
  final Widget? paymentChoice;

  /// Credits on the sign-in wallet, shown while credits are short.
  final Widget? sourceWalletNotice;

  /// The rest, below the cost: names, options.
  final List<Widget> extras;

  @override
  State<UploadReviewDialog> createState() => _UploadReviewDialogState();
}

enum _Step { review, credits }

class _UploadReviewDialogState extends State<UploadReviewDialog> {
  var _step = _Step.review;

  /// Credits bought on the way through, for saying so once they cover it.
  BigInt? _added;

  /// Between a card payment and its credits reaching the account.
  var _adding = false;

  /// With more files than this, the list shows the first [_collapsedRows]
  /// and a "+ N more" line.
  static const _maxRowsShown = 5;
  static const _collapsedRows = 4;
  var _showAllFiles = false;

  Future<void> _payByCard(int amountUsd) async {
    final balanceBefore = widget.summary?.creditsBalance ?? BigInt.zero;
    final added = await widget.funding.payByCard(amountUsd);
    if (!mounted) return;
    // Cancelled or refused: back to the review, as it was.
    if (added == null) {
      setState(() => _step = _Step.review);
      return;
    }
    setState(() {
      _step = _Step.review;
      _adding = true;
    });
    await widget.funding.awaitCredits(above: balanceBefore);
    if (!mounted) return;
    widget.funding.refresh();
    setState(() {
      _adding = false;
      _added = added;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width < 600 ? min(358.0, width - 32) : 560.0;

    if (_step == _Step.credits && widget.summary != null) {
      return AddTurboCreditsStep(
        width: dialogWidth,
        summary: widget.summary!,
        funding: widget.funding,
        onBack: () => setState(() => _step = _Step.review),
        onContinue: _payByCard,
      );
    }
    return _review(context, dialogWidth);
  }

  Widget _review(BuildContext context, double dialogWidth) {
    final l10n = appLocalizationsOf(context);
    final summary = _adding ? null : widget.summary;

    final List<ModalAction> actions = [
      ModalAction.dismiss(action: widget.onCancel, title: l10n.cancel),
      if (summary == null)
        ModalAction(
          action: () {},
          title: widget.primaryLabel,
          isEnable: false,
        )
      else if (summary.needsCredits)
        ModalAction(
          action: () => setState(() => _step = _Step.credits),
          title: l10n.uploadAddCredits,
        )
      // No price, no upload: the notice says so and offers to try again.
      else if (!summary.priceUnavailable)
        ModalAction(
          action: widget.onUpload,
          title: widget.primaryLabel,
          isEnable: summary.isCovered && widget.primaryEnabled,
        ),
    ];

    return ArDriveStandardModalNew(
      width: dialogWidth,
      scrollableContent: true,
      hasCloseButton: true,
      close: widget.onCancel,
      closeLabel: l10n.cancel,
      titleWidget: _Heading(title: widget.title, subtitle: widget.destination),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._fileRows(context),
          const SizedBox(height: ArDriveSpacing.lg),
          if (_adding)
            _Waiting(text: l10n.addingYourCredits)
          else if (summary == null)
            const _Waiting()
          else ...[
            if (!summary.priceUnavailable) UploadCostBlock(summary: summary),
            ..._notices(context, summary),
            if (summary.offersPaymentChoice || summary.usesLegacySelector)
              if (widget.paymentChoice != null) ...[
                const SizedBox(height: ArDriveSpacing.md),
                widget.paymentChoice!,
              ],
          ],
          for (final extra in widget.extras) ...[
            const SizedBox(height: ArDriveSpacing.md),
            extra,
          ],
        ],
      ),
      actions: actions,
    );
  }

  List<Widget> _notices(BuildContext context, UploadReviewSummary summary) {
    final l10n = appLocalizationsOf(context);
    final added = _added;
    return [
      if (summary.priceUnavailable)
        SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: l10n.uploadPriceUnavailable,
            actionLabel: l10n.tryAgain,
            onAction: widget.funding.refresh,
          ),
        )
      else if (summary.needsCredits) ...[
        const SizedBox(height: ArDriveSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: [
              if (summary.overFreeAllowance) l10n.uploadOverFreeAllowance,
              l10n.uploadCreditsShort(
                convertWinstonToLiteralString(summary.creditsBalance),
                convertWinstonToCostString(summary.creditsCost),
              ),
            ].join(' '),
          ),
        ),
        if (widget.sourceWalletNotice != null) ...[
          const SizedBox(height: ArDriveSpacing.md),
          widget.sourceWalletNotice!,
        ],
      ] else if (added != null &&
          !summary.isFree &&
          summary.method == UploadMethod.turbo &&
          summary.isCovered) ...[
        const SizedBox(height: ArDriveSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.success,
            message: l10n.creditsAddedLeft(
              convertWinstonToLiteralString(added),
              convertWinstonToLiteralString(summary.creditsLeftAfter),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _fileRows(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);
    final files = widget.files;
    final collapsible = files.length > _maxRowsShown;
    final shown =
        collapsible && !_showAllFiles ? files.take(_collapsedRows) : files;

    Widget row(UploadReviewFile file) => Padding(
          padding: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.sm),
            decoration: BoxDecoration(
              color: colorTokens.containerRaised,
              borderRadius: BorderRadius.circular(ArDriveRadius.md),
            ),
            child: Row(
              children: [
                getIconForContentType(
                  file.contentType,
                  size: 18,
                  color: colorTokens.iconMid,
                ),
                const SizedBox(width: ArDriveSpacing.sm),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ),
                const SizedBox(width: ArDriveSpacing.sm),
                Text(
                  filesize(file.size),
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                  ),
                ),
              ],
            ),
          ),
        );

    return [
      for (final file in shown) row(file),
      if (collapsible)
        Padding(
          padding: const EdgeInsets.only(top: ArDriveSpacing.xxs),
          child: Row(
            children: [
              ArDriveLink(
                text: _showAllFiles
                    ? l10n.showFewerFiles
                    : l10n.moreFiles(files.length - _collapsedRows),
                isAction: true,
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textMid,
                ),
                onTap: () => setState(() => _showAllFiles = !_showAllFiles),
              ),
              const Spacer(),
              Text(
                l10n.totalUploadSize(
                    filesize(files.fold<int>(0, (sum, f) => sum + f.size))),
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textLow,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

/// The title, and under it where the files go.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: typography.heading3(fontWeight: ArFontWeight.bold),
        ),
        const SizedBox(height: ArDriveSpacing.xxs),
        Text(
          subtitle,
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
      ],
    );
  }
}

/// A wait in place of the cost, with what is being waited for if it is
/// worth saying.
class _Waiting extends StatelessWidget {
  const _Waiting({this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Container(
      padding: const EdgeInsets.only(top: ArDriveSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorTokens.strokeLow)),
      ),
      height: 64,
      child: Row(
        children: [
          const ArDriveSpinner(),
          if (text != null) ...[
            const SizedBox(width: ArDriveSpacing.sm),
            Text(
              text!,
              style: typography.paragraphNormal(color: colorTokens.textMid),
            ),
          ],
        ],
      ),
    );
  }
}

/// A figure and its unit, the figure set large: a cost, or credits.
class _Figure extends StatelessWidget {
  const _Figure({required this.figure, required this.unit});

  final String figure;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: figure,
            style: typography
                .heading4(
              fontWeight: ArFontWeight.book,
              color: colorTokens.textHigh,
            )
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: ' $unit',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textMid,
              ),
            ),
        ],
      ),
    );
  }
}

/// A cost in US dollars, to the cent.
String formatUsdCost(double usd) {
  if (usd > 0 && usd < 0.01) return '< \$0.01';
  return NumberFormat.currency(locale: 'en_US', symbol: '\$').format(usd);
}

/// The upload's cost: Free, a price in US dollars paid with Turbo Credits, or
/// AR from the wallet, with a line on what that means.
class UploadCostBlock extends StatelessWidget {
  const UploadCostBlock({super.key, required this.summary});

  final UploadReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final (String figure, String unit, String note) = summary.isFree
        ? (l10n.uploadCostFree, '', l10n.uploadCostFreeNote)
        : summary.method == UploadMethod.ar
            ? (
                convertWinstonToCostString(summary.arCost),
                l10n.uploadCostArUnit,
                l10n.uploadCostWalletNote,
              )
            : summary.usdCost != null
                ? (
                    formatUsdCost(summary.usdCost!),
                    l10n.uploadCostUsdUnit,
                    l10n.uploadCostCreditsNote,
                  )
                : (
                    convertWinstonToCostString(summary.creditsCost),
                    l10n.creditsUnit,
                    l10n.uploadCostCreditsNote,
                  );

    return Container(
      padding: const EdgeInsets.only(top: ArDriveSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorTokens.strokeLow)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.uploadCostLabel,
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textLow,
                ),
              ),
              const SizedBox(height: ArDriveSpacing.xxs),
              _Figure(figure: figure, unit: unit),
            ],
          ),
          const SizedBox(width: ArDriveSpacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  note,
                  textAlign: TextAlign.right,
                  style: typography.paragraphSmall(color: colorTokens.textMid),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks an amount of Turbo Credits for this upload, then goes on to pay by
/// card.
class AddTurboCreditsStep extends StatefulWidget {
  const AddTurboCreditsStep({
    super.key,
    required this.width,
    required this.summary,
    required this.funding,
    required this.onBack,
    required this.onContinue,
  });

  final double width;
  final UploadReviewSummary summary;
  final UploadCreditsFunding funding;
  final VoidCallback onBack;
  final void Function(int amountUsd) onContinue;

  @override
  State<AddTurboCreditsStep> createState() => _AddTurboCreditsStepState();
}

class _AddTurboCreditsStepState extends State<AddTurboCreditsStep> {
  /// What each amount buys, once Turbo has said.
  Map<int, BigInt>? _credits;
  var _failed = false;
  int? _selected;
  var _continuing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _credits = null;
      _failed = false;
    });
    try {
      final credits = await Future.wait(
          addCreditsPresetsUsd.map((usd) => widget.funding.creditsFor(usd)));
      if (!mounted) return;
      final byAmount = {
        for (var i = 0; i < addCreditsPresetsUsd.length; i++)
          addCreditsPresetsUsd[i]: credits[i],
      };
      setState(() {
        _credits = byAmount;
        // The smallest amount that covers it, or the largest there is.
        _selected ??= addCreditsPresetsUsd.firstWhere(
          (usd) => _leftAfter(byAmount[usd]!) >= BigInt.zero,
          orElse: () => addCreditsPresetsUsd.last,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  BigInt _leftAfter(BigInt bought) =>
      widget.summary.creditsBalance + bought - widget.summary.creditsCost;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final credits = _credits;
    final selected = _selected;
    final bought =
        credits != null && selected != null ? credits[selected] : null;

    return ArDriveStandardModalNew(
      width: widget.width,
      scrollableContent: true,
      hasCloseButton: true,
      close: widget.onBack,
      closeLabel: l10n.back,
      titleWidget: _Heading(
        title: l10n.addTurboCreditsTitle,
        subtitle: l10n.addCreditsUploadNeeds(
            convertWinstonToCostString(widget.summary.creditsCost)),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: l10n.addCreditsAmountLabel,
            container: true,
            child: ArDriveSegmentedControl<int>(
              expand: true,
              selected: selected,
              segments: [
                for (final usd in addCreditsPresetsUsd)
                  ArDriveSegment(value: usd, label: '\$$usd'),
              ],
              onSelected: (usd) => setState(() => _selected = usd),
            ),
          ),
          const SizedBox(height: ArDriveSpacing.lg),
          if (_failed)
            SizedBox(
              width: double.infinity,
              child: ArDriveNotice(
                type: ArDriveNoticeType.error,
                message: l10n.uploadPriceUnavailable,
                actionLabel: l10n.tryAgain,
                onAction: _load,
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.only(top: ArDriveSpacing.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorTokens.strokeLow)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.addCreditsYouGet,
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textLow,
                    ),
                  ),
                  if (bought == null)
                    const ArDriveSpinner()
                  else
                    _Figure(
                      figure: convertWinstonToLiteralString(bought),
                      unit: l10n.creditsUnit,
                    ),
                ],
              ),
            ),
            if (bought != null) ...[
              const SizedBox(height: ArDriveSpacing.lg),
              Text(
                _leftAfter(bought) >= BigInt.zero
                    ? l10n.addCreditsEnough(
                        convertWinstonToLiteralString(_leftAfter(bought)))
                    : l10n.addCreditsNotEnough,
                style: typography.paragraphSmall(color: colorTokens.textMid),
              ),
            ],
          ],
        ],
      ),
      actions: [
        ModalAction.dismiss(action: widget.onBack, title: l10n.back),
        ModalAction(
          title: l10n.continueToPayment,
          isEnable: bought != null && !_continuing,
          action: () {
            final usd = _selected;
            if (usd == null) return;
            setState(() => _continuing = true);
            widget.onContinue(usd);
          },
        ),
      ],
    );
  }
}
