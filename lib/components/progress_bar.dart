import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class ProgressBar extends StatefulWidget {
  ProgressBar({Key? key, required this.percentage, this.darkMode = false})
      : super(key: key);

  final Stream<LinearProgress> percentage;
  final bool darkMode;

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  late double _percentage;
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LinearProgress>(
        stream: widget.percentage,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _percentage =
                ((snapshot.data!.progress * 100)).roundToDouble() / 100;
          } else {
            _percentage = 0;
          }

          return LinearPercentIndicator(
            animation: true,
            animateFromLastPercent: true,
            lineHeight: 10.0,
            barRadius: Radius.circular(5),
            backgroundColor:
                widget.darkMode ? Color(0xff3C3C3C) : Color(0xffFAFAFA),
            animationDuration: 1000,
            percent: _percentage,
            progressColor:
                widget.darkMode ? Color(0xffFAFAFA) : Color(0xff3C3C3C),
          );
        });
  }
}
