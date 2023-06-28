import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('FolderCreateCubit:', () {
    late Database db;

    setUp(() async {
      registerFallbackValue(ProfileStateFake());

      db = getTestDb();

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
    });

    tearDown(() async {
      await db.close();
    });
  });
}
