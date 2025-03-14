import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockWallet extends Mock implements Wallet {}

class MockArConnectWallet extends Mock implements ArConnectWallet {}

class MockArDriveIO extends Mock implements ArDriveIO {}

class MockIOFileAdapter extends Mock implements IOFileAdapter {}

void main() {
  test('Should download Wallet as IOFile correctly', () async {
    // Given
    final mockWallet = MockWallet();
    final mockArDriveIO = MockArDriveIO();
    final mockIOFileAdapter = MockIOFileAdapter();
    final walletJson = {'test': 'value'};
    final jsonString = jsonEncode(walletJson);
    final byteData = Uint8List.fromList(utf8.encode(jsonString));

    final ardriveIOUtils = ArDriveIOUtils(
      io: mockArDriveIO,
      fileAdapter: mockIOFileAdapter,
    );

    final expectedFile = await IOFileAdapter().fromData(
      byteData,
      name: 'ardrive-wallet.json',
      contentType: 'application/json',
      lastModifiedDate: DateTime(2023),
    );

    // Setup MockWallet
    when(() => mockWallet.toJwk()).thenReturn(walletJson);

    // Setup MockIOFileAdapter
    when(() => mockIOFileAdapter.fromData(
          byteData,
          name: 'ardrive-wallet.json',
          contentType: 'application/json',
          lastModifiedDate: any(named: 'lastModifiedDate'),
        )).thenAnswer((_) async => expectedFile);

    when(() => mockArDriveIO.saveFile(expectedFile)).thenAnswer((_) async {});

    // When
    final success = await ardriveIOUtils.downloadWalletAsJsonFile(
      wallet: mockWallet,
    );

    // Then
    verify(() => mockArDriveIO.saveFile(expectedFile)).called(1);
    expect(success, true);
  });

  test('Should return false if ArConnect wallet is used', () async {
    // Given
    final mockWallet = MockArConnectWallet();
    final mockArDriveIO = MockArDriveIO();
    final mockIOFileAdapter = MockIOFileAdapter();
    final walletJson = {'test': 'value'};
    final jsonString = jsonEncode(walletJson);
    final byteData = Uint8List.fromList(utf8.encode(jsonString));

    final ardriveIOUtils = ArDriveIOUtils(
      io: mockArDriveIO,
      fileAdapter: mockIOFileAdapter,
    );

    final expectedFile = await IOFileAdapter().fromData(
      byteData,
      name: 'ardrive-wallet.json',
      contentType: 'application/json',
      lastModifiedDate: DateTime(2023),
    );

    // Setup MockWallet
    when(() => mockWallet.toJwk()).thenReturn(walletJson);

    // Setup MockIOFileAdapter
    when(() => mockIOFileAdapter.fromData(
          byteData,
          name: 'ardrive-wallet.json',
          contentType: 'application/json',
          lastModifiedDate: any(named: 'lastModifiedDate'),
        )).thenAnswer((_) async => expectedFile);

    when(() => mockArDriveIO.saveFile(expectedFile)).thenAnswer((_) async {});

    // When
    expect(
      () => ardriveIOUtils.downloadWalletAsJsonFile(
        wallet: mockWallet,
      ),
      throwsA(isA<Exception>()),
    );

    // Then
    verifyNever(() => mockArDriveIO.saveFile(expectedFile));
  });

  test('Should throw an exception if fromData fails', () async {
    // Given
    final mockWallet = MockWallet();
    final mockArDriveIO = MockArDriveIO();
    final mockIOFileAdapter = MockIOFileAdapter();
    final walletJson = {'test': 'value'};
    final jsonString = jsonEncode(walletJson);
    final byteData = Uint8List.fromList(utf8.encode(jsonString));

    final ardriveIOUtils = ArDriveIOUtils(
      io: mockArDriveIO,
      fileAdapter: mockIOFileAdapter,
    );

    final expectedFile = await IOFileAdapter().fromData(
      byteData,
      name: 'ardrive-wallet.json',
      contentType: 'application/json',
      lastModifiedDate: DateTime(2023),
    );

    // Setup MockWallet
    when(() => mockWallet.toJwk()).thenReturn(walletJson);

    // Setup MockIOFileAdapter
    when(() => mockIOFileAdapter.fromData(
          byteData,
          name: 'ardrive-wallet.json',
          contentType: 'application/json',
          lastModifiedDate: any(named: 'lastModifiedDate'),
        )).thenThrow(Exception('Save file failed'));

    when(() => mockArDriveIO.saveFile(expectedFile)).thenAnswer((_) async {});

    final success = await ardriveIOUtils.downloadWalletAsJsonFile(
      wallet: mockWallet,
    );

    // When
    expect(success, false);
  });

  test('Should throw an exception if saveFile fails', () async {
    // Given
    final mockWallet = MockWallet();
    final mockArDriveIO = MockArDriveIO();
    final mockIOFileAdapter = MockIOFileAdapter();
    final walletJson = {'test': 'value'};
    final jsonString = jsonEncode(walletJson);
    final byteData = Uint8List.fromList(utf8.encode(jsonString));

    final ardriveIOUtils = ArDriveIOUtils(
      io: mockArDriveIO,
      fileAdapter: mockIOFileAdapter,
    );

    final expectedFile = await IOFileAdapter().fromData(
      byteData,
      name: 'ardrive-wallet.json',
      contentType: 'application/json',
      lastModifiedDate: DateTime(2023),
    );

    // Setup MockWallet
    when(() => mockWallet.toJwk()).thenReturn(walletJson);

    // Setup MockIOFileAdapter
    when(() => mockIOFileAdapter.fromData(
          byteData,
          name: 'ardrive-wallet.json',
          contentType: 'application/json',
          lastModifiedDate: any(named: 'lastModifiedDate'),
        )).thenAnswer((_) async => expectedFile);

    when(() => mockArDriveIO.saveFile(expectedFile))
        .thenThrow(Exception('Save file failed'));

    final success = await ardriveIOUtils.downloadWalletAsJsonFile(
      wallet: mockWallet,
    );

    // When
    expect(success, false);
  });
}
