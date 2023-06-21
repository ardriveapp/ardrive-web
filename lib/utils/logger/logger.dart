import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

final logger = Logger(
  filter: ProductionFilter(),
  level: kDebugMode ? Level.verbose : Level.info,
);
