import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockDatabase extends Mock implements Database {}

void main() {
  late _MockDatabase db;
  late MockDriveDao driveDao;

  setUp(() {
    db = _MockDatabase();
    driveDao = MockDriveDao();
    when(() => db.driveDao).thenReturn(driveDao);
  });

  test('clearing session memory clears the drive DAO', () async {
    when(() => driveDao.clearSessionMemory()).thenAnswer((_) async {});

    await DatabaseHelpers(db).clearSessionMemory();

    verify(() => driveDao.clearSessionMemory()).called(1);
  });

  test('a failure to clear is passed on, not swallowed', () async {
    // Logout reports this as a failed logout. Swallowed, it would report
    // success with drive keys still in memory.
    when(() => driveDao.clearSessionMemory())
        .thenThrow(Exception('vault would not clear'));

    await expectLater(
      DatabaseHelpers(db).clearSessionMemory(),
      throwsA(isA<Exception>()),
    );
  });
}
