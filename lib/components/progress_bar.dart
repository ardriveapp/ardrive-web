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
  double _lastPercentage = 0;
  DateTime _lastUpdate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LinearProgress>(
      stream: widget.percentage,
      builder: (context, snapshot) {
        final now = DateTime.now();
        _percentage = snapshot.hasData
            ? ((snapshot.data!.progress * 100)).roundToDouble() / 100
            : 0;

        // Disable animation for rapid updates to prevent UI lag
        final isRapidUpdate = now.difference(_lastUpdate).inMilliseconds < 200;
        final hasSignificantChange = (_percentage - _lastPercentage).abs() > 0.05;
        
        _lastPercentage = _percentage;
        _lastUpdate = now;

        return LinearPercentIndicator(
          animation: !isRapidUpdate && hasSignificantChange,
          animateFromLastPercent: true,
          lineHeight: 10.0,
          barRadius: const Radius.circular(5),
          backgroundColor: const Color(0xffFAFAFA),
          animationDuration: 100,
          percent: _percentage,
          progressColor: const Color(0xff3C3C3C),
        );
      },
    );
  }
}
