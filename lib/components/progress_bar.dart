import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

class ProgressBar extends StatefulWidget {
  const ProgressBar({Key? key, required this.percentage}) : super(key: key);

  final Stream<LinearProgress> percentage;

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

          return ArDriveProgressBar(percentage: _percentage);
        });
  }
}
