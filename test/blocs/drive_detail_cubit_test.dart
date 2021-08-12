// import 'package:ardrive/blocs/blocs.dart';
// import 'package:ardrive/models/models.dart';
// import 'package:cryptography/cryptography.dart';
// import 'package:cryptography/helpers.dart';
// import 'package:mockito/mockito.dart';
// import 'package:moor/moor.dart';
// import 'package:test/test.dart';

// import '../utils/utils.dart';

// void main() {
//   group('DriveDetailCubit:', () {
//     Database db;
//     DriveDao driveDao;

//     ProfileCubit profileCubit;
//     DriveDetailCubit driveDetailCubit;

//     const mockDriveId = 'mock-drive-id';

//     setUp(() {
//       db = getTestDb();
//       driveDao = db.driveDao;

//       profileCubit = MockProfileCubit();

//       final keyBytes = Uint8List(32);
//       fillBytesWithSecureRandom(keyBytes);

//       when(profileCubit.state).thenReturn(
//         ProfileLoggedIn(
//           username: '',
//           password: '123',
//           wallet: getTestWallet(),
//           cipherKey: SecretKey(keyBytes),
//         ),
//       );

//       driveDetailCubit = DriveDetailCubit(
//         driveId: mockDriveId,
//         profileCubit: profileCubit,
//         driveDao: driveDao,
//       );
//     });

//     tearDown(() async {
//       await db.close();
//     });
//   });
// }
