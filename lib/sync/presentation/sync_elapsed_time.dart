import 'dart:async';

import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// How long the running sync has taken: seconds under a minute, minutes and
/// seconds above, the way the sync history says how long a sync took. "1200s"
/// is not a number anybody reads.
String formatSyncElapsed(BuildContext context, Duration elapsed) {
  final seconds = elapsed.inSeconds;
  if (seconds < 60) {
    return appLocalizationsOf(context).syncElapsedTime(seconds.toString());
  }
  return appLocalizationsOf(context).syncElapsedTimeMinutes(
    (seconds ~/ 60).toString(),
    (seconds % 60).toString(),
  );
}

/// Time since the running sync started.
///
/// Shown wherever a running sync reports itself - the status header inside the
/// sync indicator's menu, and the explorer panel a drive click lands on -
/// because a wait that counts is a wait that is working, and one that does not
/// is a hang. Both read [SyncCubit.syncStartTime], so they can never disagree
/// about how long this has been going on.
///
/// Only mount this while a sync is actually running: `syncStartTime` keeps the
/// last sync's start, so an idle surface counting from it would report minutes.
class SyncElapsedTime extends StatefulWidget {
  const SyncElapsedTime({super.key});

  @override
  State<SyncElapsedTime> createState() => _SyncElapsedTimeState();
}

class _SyncElapsedTimeState extends State<SyncElapsedTime> {
  // Held in a field, not built in `build`: progress events rebuild this widget
  // often, and a stream rebuilt each time restarts its timer before it fires,
  // so the counter would tick to the sync's cadence instead of the clock's.
  final Stream<int> _ticks =
      Stream.periodic(const Duration(seconds: 1), (i) => i);

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        final elapsed =
            DateTime.now().difference(context.read<SyncCubit>().syncStartTime);

        return Text(
          formatSyncElapsed(context, elapsed),
          // `textMid`, not `textLow`. The quieter token is #7d7d7d, and the
          // darkest surface this is drawn on is #191919: 4.27:1, under WCAG
          // AA's 4.5:1 for body text. This is the only place elapsed time is
          // reported, so it is not decoration that can afford to be faint - it
          // is the line that says a long wait is still moving.
          style: typography.paragraphSmall(color: colorTokens.textMid),
        );
      },
    );
  }
}
