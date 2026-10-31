import 'dart:math';

import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// One file on the upload review.
typedef UploadReviewFile = ({String name, int size, String contentType});

/// The amounts offered on the Add Turbo Credits step, in US dollars.
const addCreditsPresetsUsd = [10, 25, 50, 100];

/// What the review is paying for, which its notices name: an upload, or a
/// change such as a license.
enum ReviewCostSubject { upload, change }

/// The review's notices about paying, worded for its [ReviewCostSubject].
class ReviewCostCopy {
  ReviewCostCopy(this._l10n, this.subject);

  final AppLocalizations _l10n;
  final ReviewCostSubject subject;

  bool get _upload => subject == ReviewCostSubject.upload;

  String get overFreeAllowance =>
      _upload ? _l10n.uploadOverFreeAllowance : _l10n.changeOverFreeAllowance;

  String creditsShort(String balance, String cost) => _upload
      ? _l10n.uploadCreditsShort(balance, cost)
      : _l10n.changeCreditsShort(balance, cost);

  String get priceUnavailable =>
      _upload ? _l10n.uploadPriceUnavailable : _l10n.changePriceUnavailable;

  String needs(String cost) => _upload
      ? _l10n.addCreditsUploadNeeds(cost)
      : _l10n.addCreditsChangeNeeds(cost);

  String enough(String left) => _upload
      ? _l10n.addCreditsEnough(left)
      : _l10n.addCreditsEnoughChange(left);

  String get notEnough =>
      _upload ? _l10n.addCreditsNotEnough : _l10n.addCreditsNotEnoughChange;

  String addedLeft(String added, String left) => _upload
      ? _l10n.creditsAddedLeft(added, left)
      : _l10n.creditsAddedLeftChange(added, left);
}

/// How the upload review buys Turbo Credits: what an amount buys, paying for
/// it by card, and waiting for the credits to arrive.
abstract class UploadCreditsFunding {
  /// The Turbo Credits [amountUsd] buys, in winston credits, live from Turbo.
  Future<BigInt> creditsFor(int amountUsd);

  /// Pays [amountUsd] by card. The credits bought, or null when the payment
  /// was cancelled or did not go through.
  Future<BigInt?> payByCard(int amountUsd);

  /// Waits for the balance to rise above [above]: true once it has, false if
  /// it has not after a while.
  Future<bool> awaitCredits({required BigInt above});

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
    this.canShareInApp = false,
    this.extras = const [],
    this.onShown,
    this.leading = const [],
    this.onBack,
    this.subject = ReviewCostSubject.upload,
    this.priceUnavailableMessage,
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

  /// Starts the upload, paid the way the summary says. The method is passed
  /// on so the upload uses exactly what the review showed.
  final void Function(UploadMethod method) onUpload;
  final VoidCallback onCancel;
  final UploadCreditsFunding funding;

  /// Called once, when the review is first shown.
  final VoidCallback? onShown;

  /// The wallet-or-credits choice, shown when the summary offers one.
  final Widget? paymentChoice;

  /// Credits on the sign-in wallet, shown while credits are short.
  final Widget? sourceWalletNotice;

  /// Whether [sourceWalletNotice] carries a Share credits button that works
  /// here. Without one, sharing is a trip to Turbo, so Add credits stays the
  /// way forward.
  final bool canShareInApp;

  /// The rest, below the cost: names, options.
  final List<Widget> extras;

  /// Above the cost, after the files: what a change is, such as a license.
  final List<Widget> leading;

  /// When set, the secondary action is Back, to the step before, rather than
  /// Cancel. The close button still cancels.
  final VoidCallback? onBack;

  /// What is being paid for, which the notices name.
  final ReviewCostSubject subject;

  /// In place of the usual no-price notice, which blames the connection,
  /// when the cause was something else.
  final String? priceUnavailableMessage;

  @override
  State<UploadReviewDialog> createState() => _UploadReviewDialogState();
}

enum _Step { review, credits }

class _UploadReviewDialogState extends State<UploadReviewDialog> {
  var _step = _Step.review;

  /// Credits bought on the way through, for saying so once they cover it.
  BigInt? _added;

  /// Between a card payment and the review showing its credits. Until then
  /// the review shows the wait, never the summary from before the payment.
  var _adding = false;

  /// The credits have not arrived in the time it waited: it offers to check
  /// again rather than going back to Add credits. Once they arrive, the wait
  /// ends with the fresh read, whatever it says.
  var _slow = false;

  /// A read of the price and balance is under way, and has not yet started
  /// loading. See [didUpdateWidget].
  var _refreshing = false;
  var _sawLoading = false;

  /// The balance before the payment, for knowing when its credits are in.
  BigInt _balanceBefore = BigInt.zero;

  @override
  void initState() {
    super.initState();
    widget.onShown?.call();
  }

  @override
  void didUpdateWidget(UploadReviewDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_refreshing) return;
    final summary = widget.summary;
    if (summary == null) {
      _sawLoading = true;
      return;
    }
    if (!_sawLoading) return;
    // The fresh read is in. It is only asked for once the credits have
    // arrived, so the wait is over either way: covered, it offers Upload;
    // still short, as when the amount bought was too small, it says so, and
    // offers Add credits again. Waiting on would wait for ever.
    _refreshing = false;
    _sawLoading = false;
    _adding = false;
    _slow = false;
  }

  void _refresh() {
    _refreshing = true;
    _sawLoading = false;
    widget.funding.refresh();
  }

  Future<void> _checkAgain() async {
    setState(() => _slow = false);
    final landed = await widget.funding.awaitCredits(above: _balanceBefore);
    if (!mounted) return;
    if (landed) {
      _refresh();
    } else {
      setState(() => _slow = true);
    }
  }

  /// With more files than this, the list shows the first [_collapsedRows]
  /// and a "+ N more" line.
  static const _maxRowsShown = 5;
  static const _collapsedRows = 4;
  var _showAllFiles = false;

  Future<void> _payByCard(int amountUsd) async {
    _balanceBefore = widget.summary?.creditsBalance ?? BigInt.zero;
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
      _slow = false;
      _added = added;
    });
    final landed = await widget.funding.awaitCredits(above: _balanceBefore);
    if (!mounted) return;
    if (landed) {
      _refresh();
    } else {
      setState(() => _slow = true);
    }
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
        subject: widget.subject,
      );
    }
    return _review(context, dialogWidth);
  }

  Widget _review(BuildContext context, double dialogWidth) {
    final l10n = appLocalizationsOf(context);
    final summary = _adding ? null : widget.summary;
    final shareFirst = summary != null && _shareFirst(summary);

    final List<ModalAction> actions = [
      ModalAction.dismiss(
        action: widget.onBack ?? widget.onCancel,
        title: widget.onBack != null ? l10n.back : l10n.cancel,
      ),
      if (summary == null)
        ModalAction(
          action: () {},
          title: widget.primaryLabel,
          isEnable: false,
        )
      // Credits on the sign-in wallet cover it: Share credits, in their notice,
      // is the way forward, and Add credits steps back to a link below it.
      else if (summary.needsCredits && !shareFirst)
        ModalAction(
          action: () => setState(() => _step = _Step.credits),
          title: l10n.uploadAddCredits,
        )
      // No price, no upload: the notice says so and offers to try again.
      else if (!summary.priceUnavailable)
        ModalAction(
          action: () => widget.onUpload(summary.method),
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
          ...widget.leading,
          const SizedBox(height: ArDriveSpacing.lg),
          if (_adding)
            _Waiting(
              text: l10n.addingYourCredits,
              actionLabel: _slow ? l10n.checkAgain : null,
              onAction: _checkAgain,
            )
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

  /// Short of credits, and the sign-in wallet's would cover it once shared,
  /// with their notice on screen and its Share credits button working here.
  bool _shareFirst(UploadReviewSummary summary) =>
      summary.signInCreditsCover &&
      widget.sourceWalletNotice != null &&
      widget.canShareInApp;

  List<Widget> _notices(BuildContext context, UploadReviewSummary summary) {
    final l10n = appLocalizationsOf(context);
    final copy = ReviewCostCopy(l10n, widget.subject);
    final added = _added;
    return [
      if (summary.priceUnavailable)
        SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: widget.priceUnavailableMessage ?? copy.priceUnavailable,
            actionLabel: l10n.tryAgain,
            onAction: _refresh,
          ),
        )
      // A change paid from the wallet, which can't cover it. An upload says
      // so in its payment selector instead.
      else if (widget.subject == ReviewCostSubject.change &&
          summary.method == UploadMethod.ar &&
          !summary.isCovered) ...[
        const SizedBox(height: ArDriveSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: l10n.changeWalletShort,
          ),
        ),
      ] else if (summary.needsCredits) ...[
        const SizedBox(height: ArDriveSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: [
              if (summary.overFreeAllowance) copy.overFreeAllowance,
              copy.creditsShort(
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
        if (_shareFirst(summary)) ...[
          const SizedBox(height: ArDriveSpacing.sm),
          ArDriveLink(
            text: l10n.uploadAddCredits,
            isAction: true,
            onTap: () => setState(() => _step = _Step.credits),
          ),
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
            message: copy.addedLeft(
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
  const _Waiting({this.text, this.actionLabel, this.onAction});

  final String? text;

  /// A way out of a wait that has gone on too long, such as Check again.
  final String? actionLabel;
  final VoidCallback? onAction;

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
          if (actionLabel != null) ...[
            const Spacer(),
            ArDriveLink(
              text: actionLabel!,
              isAction: true,
              onTap: onAction,
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
    this.subject = ReviewCostSubject.upload,
  });

  final double width;
  final UploadReviewSummary summary;
  final UploadCreditsFunding funding;
  final VoidCallback onBack;
  final void Function(int amountUsd) onContinue;
  final ReviewCostSubject subject;

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
    final copy = ReviewCostCopy(l10n, widget.subject);
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
        subtitle:
            copy.needs(convertWinstonToCostString(widget.summary.creditsCost)),
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
                message: copy.priceUnavailable,
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
                    ? copy.enough(
                        convertWinstonToLiteralString(_leftAfter(bought)))
                    : copy.notEnough,
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
