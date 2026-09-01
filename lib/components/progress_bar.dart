import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The bar the sync modal fills.
///
/// One widget type fills this slot in both phases, and that is the whole
/// design. The bar used to return a [LinearProgressIndicator] while a phase
/// could not measure itself and a `LinearPercentIndicator` when it could - two
/// types in one position, so `Widget.canUpdate` failed on the swap, Flutter
/// unmounted the element and percent_indicator built a fresh
/// `Tween(begin: 0.0, end: percent)` in `initState` and animated it. Leaving
/// the unmeasurable phase at 97% therefore emptied the bar and refilled it over
/// a full second, which is exactly the backwards-moving bar the sync's
/// monotonic progress exists to prevent, reintroduced one layer up. It fired
/// for anyone with pending transactions - anyone who had uploaded recently.
///
/// [LinearProgressIndicator] already draws both: it is indeterminate exactly
/// when its `value` is null. Same distinction, no swap, and the element - with
/// whatever its fill is currently doing - survives the transition.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.percentage,
    this.initialPercentage,
  });

  final Stream<LinearProgress> percentage;

  /// What the bar reads before [percentage] delivers anything.
  ///
  /// The sync modal mounts when a sync starts, so an empty bar is the truth
  /// for it and it passes nothing. A bar that mounts *during* a sync - the
  /// explorer's, when a drive is clicked while one runs - would otherwise sit
  /// at zero until the next progress event, which in the unmeasurable phase
  /// is up to half a minute of a bar claiming a number that is already wrong.
  final LinearProgress? initialPercentage;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return StreamBuilder<LinearProgress>(
      stream: percentage,
      initialData: initialPercentage,
      builder: (context, snapshot) {
        final progress = snapshot.data;

        // A phase that cannot know its own length gets a bar that does not
        // claim to - see [LinearProgress.isIndeterminate]. The alternative is
        // a number sitting perfectly still for up to half a minute, which is
        // what a hung app looks like.
        final isIndeterminate = progress?.isIndeterminate ?? false;
        final value = progress == null
            ? 0.0
            : ((progress.progress * 100).roundToDouble() / 100).clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: const BorderRadius.all(_barRadius),
          // percent_indicator animated between values for free; a plain
          // indicator jumps. [TweenAnimationBuilder] restarts from wherever the
          // fill currently is rather than from zero, so a new value is walked
          // to and never rewound to the start of the bar.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value),
            duration: _barAnimation,
            builder: (context, animated, _) => LinearProgressIndicator(
              value: isIndeterminate ? null : animated,
              minHeight: _barHeight,
              backgroundColor: colorTokens.strokeHigh,
              // The same token the top bar's ring fills with. This drew in
              // `textHigh` while the ring above it and the drives list drew in
              // the accent, so one sync reported itself in two colours
              // depending on which screen you were looking at.
              valueColor: AlwaysStoppedAnimation<Color>(
                colorTokens.buttonPrimaryDefault,
              ),
            ),
          ),
        );
      },
    );
  }
}

const _barHeight = 10.0;
const _barRadius = Radius.circular(5);

/// How long the fill takes to travel between two values - percent_indicator's
/// `animationDuration`, kept so the bar still moves at the speed it did.
const Duration _barAnimation = Duration(milliseconds: 1000);
