import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

void main() {
  late MockDriveDao driveDao;
  late FileKeys fileKeys;
  final cipherKey = SecretKey(List.filled(32, 1));
  final driveKey = DriveKey(SecretKey(List.filled(32, 2)), true);
  final fileKey = SecretKey(List.filled(32, 3));

  setUpAll(() => registerFallbackValue(SecretKey(const [0])));

  setUp(() {
    driveDao = MockDriveDao();
    fileKeys = FileKeys(driveDao: driveDao);
    when(() => driveDao.getFileKey('file', driveKey.key))
        .thenAnswer((_) async => fileKey);
  });

  test('a signed-in profile opens the drive key it stored', () async {
    when(() => driveDao.getDriveKey('drive', cipherKey))
        .thenAnswer((_) async => driveKey);

    final key = await fileKeys.keyFor(
        driveId: 'drive', fileId: 'file', cipherKey: cipherKey);

    expect(key, same(fileKey));
    verifyNever(() => driveDao.getDriveKeyFromMemory(any()));
  });

  test('a visitor uses the drive key held in memory', () async {
    when(() => driveDao.getDriveKeyFromMemory('drive'))
        .thenAnswer((_) async => driveKey);

    final key = await fileKeys.keyFor(
        driveId: 'drive', fileId: 'file', cipherKey: null);

    expect(key, same(fileKey));
    verifyNever(() => driveDao.getDriveKey(any(), any()));
  });

  test('no drive key, no file key', () async {
    when(() => driveDao.getDriveKey('drive', cipherKey))
        .thenAnswer((_) async => null);
    when(() => driveDao.getDriveKeyFromMemory('drive'))
        .thenAnswer((_) async => null);

    expect(
        await fileKeys.keyFor(
            driveId: 'drive', fileId: 'file', cipherKey: cipherKey),
        isNull);
    expect(await fileKeys.forDrive('drive', cipherKey: null), isNull);
    verifyNever(() => driveDao.getFileKey(any(), any()));
  });

  test('a ring asks for the drive key once, for many files', () async {
    when(() => driveDao.getDriveKey('drive', cipherKey))
        .thenAnswer((_) async => driveKey);
    when(() => driveDao.getFileKey('other', driveKey.key))
        .thenAnswer((_) async => SecretKey(List.filled(32, 4)));

    final ring = (await fileKeys.forDrive('drive', cipherKey: cipherKey))!;
    await ring.keyFor('file');
    await ring.keyFor('other');

    verify(() => driveDao.getDriveKey('drive', cipherKey)).called(1);
  });

  test("a file's key is the one ArFS derives from its drive key", () async {
    // The real derivation, not a mock: what every reader got before.
    final crypto = ArDriveCrypto();
    final realDriveKey = DriveKey(SecretKey(List.filled(32, 7)), true);
    when(() => driveDao.getDriveKeyFromMemory('drive'))
        .thenAnswer((_) async => realDriveKey);
    when(() => driveDao.getFileKey(any(), any())).thenAnswer((call) =>
        crypto.deriveFileKey(call.positionalArguments[1] as SecretKey,
            call.positionalArguments[0] as String));

    final key = await fileKeys.keyFor(
        driveId: 'drive',
        fileId: '2b7c9e1d-4f3a-4c8b-9e2d-1a0b3c4d5e6f',
        cipherKey: null);

    expect(
      await key!.extractBytes(),
      await (await crypto.deriveFileKey(
              realDriveKey.key, '2b7c9e1d-4f3a-4c8b-9e2d-1a0b3c4d5e6f'))
          .extractBytes(),
    );
  });
}
