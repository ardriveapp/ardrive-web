import 'dart:async';

import 'package:alchemist/alchemist.dart';

void testExecutable(FutureOr<void> Function() testMain) async {
  return AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      ciGoldensConfig: CiGoldensConfig(),
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
    ),
    run: testMain,
  );
}
