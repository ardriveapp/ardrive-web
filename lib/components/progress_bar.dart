import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class ProgressBar extends StatefulWidget {
  const ProgressBar({super.key, required this.percentage});

  final Stream<LinearProgress> percentage;

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  late double _percentage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LinearProgress>(
      stream: widget.percentage,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _percentage = ((snapshot.data!.progress * 100)).roundToDouble() / 100;
        } else {
          _percentage = 0;
        }

        return LinearPercentIndicator(
          animation: true,
          animateFromLastPercent: true,
          lineHeight: 10.0,
          barRadius: const Radius.circular(5),
          backgroundColor: const Color(0xffFAFAFA),
          animationDuration: 1000,
          percent: _percentage,
          progressColor: const Color(0xff3C3C3C),
        );
      },
    );
  }
}
