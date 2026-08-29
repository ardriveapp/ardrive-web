import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class ProgressBar extends StatefulWidget {
  const ProgressBar({super.key, required this.percentage});

  final Stream<LinearProgress> percentage;

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

const _barTrack = Color(0xffFAFAFA);
const _barFill = Color(0xff3C3C3C);
const _barHeight = 10.0;
const _barRadius = Radius.circular(5);

class _ProgressBarState extends State<ProgressBar> {
  late double _percentage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LinearProgress>(
      stream: widget.percentage,
      builder: (context, snapshot) {
        // A phase that cannot know its own length gets a bar that does not
        // claim to - see [LinearProgress.isIndeterminate]. The alternative is
        // a number sitting perfectly still for up to half a minute, which is
        // what a hung app looks like.
        if (snapshot.hasData && snapshot.data!.isIndeterminate) {
          return const ClipRRect(
            borderRadius: BorderRadius.all(_barRadius),
            child: LinearProgressIndicator(
              minHeight: _barHeight,
              backgroundColor: _barTrack,
              valueColor: AlwaysStoppedAnimation<Color>(_barFill),
            ),
          );
        }

        _percentage = snapshot.hasData
            ? ((snapshot.data!.progress * 100)).roundToDouble() / 100
            : 0;

        return LinearPercentIndicator(
          animation: true,
          animateFromLastPercent: true,
          lineHeight: _barHeight,
          barRadius: _barRadius,
          backgroundColor: _barTrack,
          animationDuration: 1000,
          percent: _percentage,
          progressColor: _barFill,
        );
      },
    );
  }
}
