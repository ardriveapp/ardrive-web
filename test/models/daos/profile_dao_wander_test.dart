import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

void main() {
  late Database db;

  setUp(() => db = getTestDb());
  tearDown(() => db.close());

  test(
      'unlocking a saved Wander account knows its address without asking '
      'Wander', () async {
    // Stands in for Wander at sign-up; only its keys are read.
    final wanderWallet = getTestWallet();
    await db.profileDao.addProfile(
      'user',
      'password',
      wanderWallet,
      ProfileType.arConnect,
    );

    final unlocked = await db.profileDao.loadDefaultProfile('password');

    // Outside a browser every call to Wander throws, so these answering
    // proves they were not asked.
    expect(await unlocked.wallet.getAddress(), await wanderWallet.getAddress());
    expect(await unlocked.wallet.getOwner(), await wanderWallet.getOwner());
  });
}
