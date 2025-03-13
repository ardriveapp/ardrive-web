import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockWallet extends Mock implements Wallet {}

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
    await ardriveIOUtils.downloadWalletAsJsonFile(
      wallet: mockWallet,
    );

    // Then
    verify(() => mockArDriveIO.saveFile(expectedFile)).called(1);
  });

  test('Should call success callback when download is successful', () async {
    // Given
    final mockWallet = MockWallet();
    final mockArDriveIO = MockArDriveIO();
    final mockIOFileAdapter = MockIOFileAdapter();
    final walletJson = {'test': 'value'};
    final jsonString = jsonEncode(walletJson);
    final byteData = Uint8List.fromList(utf8.encode(jsonString));
    bool? callbackResult;

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
    await ardriveIOUtils.downloadWalletAsJsonFile(
      wallet: mockWallet,
      onDownloadComplete: (success) {
        callbackResult = success;
      },
    );

    // Then
    verify(() => mockArDriveIO.saveFile(expectedFile)).called(1);
    expect(callbackResult, true);
  });

  test('Should call failure callback when download throws an exception',
      () async {
    // Given
    final mockWallet = MockWallet();
    final mockArDriveIO = MockArDriveIO();
    final mockIOFileAdapter = MockIOFileAdapter();
    final walletJson = {'test': 'value'};
    final jsonString = jsonEncode(walletJson);
    final byteData = Uint8List.fromList(utf8.encode(jsonString));
    bool? callbackResult;

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
        .thenThrow(Exception('Failed to save file'));

    // When
    try {
      await ardriveIOUtils.downloadWalletAsJsonFile(
        wallet: mockWallet,
        onDownloadComplete: (success) {
          callbackResult = success;
        },
      );
      fail('Expected an exception');
    } catch (e) {
      // Expected exception
    }

    // Then
    verify(() => mockArDriveIO.saveFile(expectedFile)).called(1);
    expect(callbackResult, false);
  });
}
