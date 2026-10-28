import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// How long a price quote has left, on one line, with a way to refresh it.
///
/// The same line on every top-up screen that holds a quote: a clock, "Price
/// valid for mm:ss" ("Quote expired" once it runs out), and a refresh button.
/// The line hugs its content, so the caller places it.
class QuoteTimer extends StatefulWidget {
  const QuoteTimer({
    super.key,
    this.expiresAt,
    this.secondsLeft,
    this.isLoading = false,
    this.errorMessage,
    required this.onRefresh,
    this.onExpired,
  }) : assert(expiresAt != null || secondsLeft != null);

  /// When the quote expires. Give this or [secondsLeft].
  final DateTime? expiresAt;

  /// How many seconds the quote has left as of now. The countdown restarts
  /// when this value changes.
  final int? secondsLeft;

  /// A new quote is being fetched: the refresh button is a spinner.
  final bool isLoading;

  /// Shown in place of the countdown when the quote could not be fetched.
  final String? errorMessage;

  final VoidCallback onRefresh;

  /// Called once when the countdown reaches zero.
  final VoidCallback? onExpired;

  @override
  State<QuoteTimer> createState() => _QuoteTimerState();
}

class _QuoteTimerState extends State<QuoteTimer> {
  late DateTime _deadline;
  Timer? _ticker;
  bool _expiredReported = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(QuoteTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expiresAt != oldWidget.expiresAt ||
        widget.secondsLeft != oldWidget.secondsLeft) {
      _start();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _deadline = widget.expiresAt ??
        DateTime.now().add(Duration(seconds: widget.secondsLeft!));
    _expiredReported = false;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_remaining <= Duration.zero && !_expiredReported) {
      _expiredReported = true;
      _ticker?.cancel();
      widget.onExpired?.call();
    }
  }

  Duration get _remaining => _deadline.difference(DateTime.now());

  /// mm:ss, rounded up, so a fresh 2-minute quote reads 02:00, not 01:59.
  String _format(Duration remaining) {
    final total = (remaining.inMilliseconds / 1000).ceil();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final errorMessage = widget.errorMessage;
    final remaining = _remaining;
    final isExpired = remaining <= Duration.zero;

    final String text;
    final Color color;
    if (errorMessage != null) {
      text = errorMessage;
      color = colors.statusErrorFg;
    } else if (isExpired) {
      text = 'Quote expired';
      color = colors.statusErrorFg;
    } else {
      text = 'Price valid for ${_format(remaining)}';
      color = colors.textMid;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorMessage == null) ...[
          ExcludeSemantics(
            child: Icon(Icons.schedule, size: 14, color: colors.textMid),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: typography.paragraphSmall(
              color: color,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox.square(
          dimension: 28,
          child: widget.isLoading
              ? Center(child: ArDriveSpinner(color: colors.textMid))
              : _RefreshButton(onRefresh: widget.onRefresh),
        ),
      ],
    );
  }
}

/// The refresh: a named button a keyboard can reach.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onRefresh});

  final VoidCallback onRefresh;

  static const _label = 'Refresh quote';

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return Semantics(
      button: true,
      label: _label,
      excludeSemantics: true,
      onTap: onRefresh,
      child: Tooltip(
        message: _label,
        child: InkWell(
          onTap: onRefresh,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Icon(Icons.refresh, size: 16, color: colors.textMid),
          ),
        ),
      ),
    );
  }
}
