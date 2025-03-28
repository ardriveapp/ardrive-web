import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:html';
import 'dart:math';

import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

export 'matchers.dart';
export 'mocks.dart';

Database getTestDb() => Database(NativeDatabase.memory());

String getWalletString = '''
  {
    "kty": "RSA",
    "e": "AQAB",
    "n": "kmM4O08BJB85RbxfQ2nkka9VNO6Czm2Tc_IGQNYCTSXRzOc6W9bHRrlZ_eDhWO0OdfaRalgLeuYCXx9DV-n1djeerKHdFo2ZAjRv5WjL_b4IxbQnPFnHOSNHVg49yp7CUWUgDQOKtylt3x0YENIW37RQPZJ-Fvyk7Z0jvibj2iZ0K3K8yNenJ4mWswyQdyPaJcbP6AMWvUWT62giWHa3lDgBZNhXqakkYdoaM157kRUfrZDRSWXbilr-4f40PQF1DV5YSj81Fl72N7j30r0vL1yoj0bZn74WRquQ5j3QsiAA-SzhAxpecWniljj1wvZlyIgJpCYCvCrKZCcCq_JW1nYP6to5YM3fAqcYRadbTNdQ3oH0Sjy8vyvLYNe48Ur_TFTTAwZxJV70BgZfkJ00BxiNTb8EhSchejabeExUkCNlOrQsCHDxOig-WXOrjX5fb4NeR3jedeYWbhN922ORLuEwVLeyjc7hBfQXU2-mYraFAVTc0QST201P7rRu-UGtZ4gRavFuOvAyYrMimFVW9dTwTrcYXFK2zKCEv2aRRQAHZanKjBv0Xq9m3BqvxKy-_3Cj1O6ft7FT21drPoDRDzfnkyOeUjlXzRJzn-iQ0nqgHAQr9WBWPzLEcaTFpw3KmwDYHW_6JOkUWDyMW9anuS8cyqt_2O29SK_rHHuucD8",
    "d": "Bq6C13vknF6Ln1MrKI3Ilq-83IuSvQpe7NRAuT69u7i8sv4XwsHOJAV7qpGvp37NXT5R1G3ehEZ6qoSxJbcN4IVrQMKq5mMiCY6DBv5C6fHZGoNZE2gxXV7uydf8I1Vnnw4xYIj5oyC_5nSJlFAc3U-MAcbkfJuvrhGxLVGsrqHmjoqQPGG_hTxCjuAOlOBs-9cmWTujbm1-OyjaAQwfTbXYbUy7hC1TCE05SxLPmTUwaJxY8AXJigpbYqjpWsc15HjRlv38A44tEnIwHjHda_3JpmbSsffSslRej2vPCCgSPHHyLeO437Nc7DraogKStugisRfhoe89yY4QSBVXbtvWJeF1LxPtg8uPtfoKt3wdnGWKaLDqYNDeA3AckbKrPp50kHEMR7hnNHq3lAoMAXTz8BbI_Czo5n9-f9DQpvJC8kpM7gCGG8DptA2nTPuQG02MOx7AsEE99EN8ltD_dA0l0MgG7CDsaQC5IPMHcRs1wyvZMBGA8fvZdURiVv9YSnCddndXjBJuetf5KdES-1EmrSLzo5hobQbkc7dkHMS5dmLm5YtK-aLYXZi31nRIGkA1UfZhf2TtfRxP6uKlRT106EtDX1rT3RgsLqg06y_xoS4SFQ6u-8wHqgbIHBmKdsWVtBkC4SGUlYDPgrJe2V9CaPFAcoSDFK1D_IPvU2U",
    "p": "zhyauK0ISMg9Wk7iZK2ifW2cj5KSr-_k_Em0nfUrtsaKp0iXOsCKxOH__zcAVj7oLxaEP2l8i2Pdi7CzhVRiqrjgVwA1JuLPgxtryuVqwRCYbO_Y_2Xutk404iKmDX6_LQ7BeIzUI8GD6rQCeLq1HBd3Yvok9bPvbbMZjFtUmBf_Kfb0cYP8tewMmV_USGpqwJXdB_4aHF6qBrZBtd1KLoO1E7MNkAPk7pbiA1-KO2Xa6oY6fy2pztNe1MO7tz_QywqlDdymfhnpk41arY3A6US-ZFXOinqXKdh9uEfxiyZwzaLMNWVKEaWxRxbqSUOLV3uZS05N6B2ZqvOp2h9Csw",
    "q": "tdHmYcbJpZ0U27d_j0YvUeb6sdcuFLg2vmDgKwUamC5_vvV41LSm8LIkLuY2DAN5MKg6-HTWetKWQhgbCIbubLtX5164MFrES1YVZI-aggrYohhH8MRn_hwMZZQndv9H07WUVgQ1GZ2ZDvhO7XxPDIXyBNQ46x6V1AikHtyTmqARjgrkgs-1XN55S9rhcffixOlJ-egIDPVei_Z6YNdSpLlhtiqHOp_lX37mrPSYGxjgIZVxevpPgBhVFlnAMqC2iRd87XupmWgiluSos8I7i1VESBzwlFZGk5hRb8och4zwmDBDwx65XWngg6LneSXTWcKjKKGM2NnX7wHrZBuyRQ",
    "dp": "Gfo49fW5CZNTSEKQ_id0R2K9TMsoecw-jB2uCgqQi-TSLOtVRC5oTxA896my_SvIj8bCvEtLSzY3AhgvSCqulN3gSJbaHCCSDvAx0czAe7zfuTsxml76izeoKqg7TZAgAEnP0KXPRwJo4ff2J8lAcl3yyiLE7cLT9nuQSMRqERFVM7DQdk4wV618mQge9VGUStmYlh1MpS65N0dZWNafNuWauPTkTLZw8DFMIyizf3EC-nQYg1b6A_tYBHD3A82jPzQEQY8B3PrfGZ3DRASNv9jONk8qTQHOc5O5pLRMmUErDn_qRQCTKU483bzhooJE2a3WUEt6Pjsc1xMG4Vr3SQ",
    "dq": "cCVai36Yi-06m1cwd8fbkhH9GUpXIvKI2Z5ZRk-smqc7piY0dEZFHftS9BaMyZYu3wM09GDklfdkNLo3mmfXkftv-cbjpvelUa50HYWx0HouKrT9UpVia0sTnmfme7BztjKunuuTcQxTBvfDfxoIi_nmUHIx9Vv1IEaALITzChGnIky3q7O_8ttKR65nFevG1JvsRBeJN6z0tzG9RBQr5mxtx3Wt2Uwcp21XjOCFHVmXjT9nMmpINQNNIC8VrGSSkjaJmNWIw5WGmDnLkKzCG2vpZO1suqIIgCsYN_Ka7ETTdZt3gFdoECUpFSiay4-4MAospvgWLv8XAFXXwfSPXQ",
    "qi": "n-R81MpbwfWfqRSVgD8nDk7D8zlJ-tpMaojfTwNNqDt34Cr-BpMjxaQyEfMnzOd2dY4OV0rKhd29DIuwFEb2UERHdVWF3gM8f2byYGj4357CRkiwq6I050bUxd1ODgAXjVGNpOK_fmaNHDWfe5v3wVIcCmwH0mJxEu9kuz7fr9TJNxGJBGUphpGS6NQZDCbDXg9-FPafMeNV-Jdo0NQaKMwm8uZyW7YGSNpUXYnksrWt4Fa-B9H2KoC4PPSWESPxNooXdxK7Y0J1KbzNyrUmOl4dT6p_oFKcU-1unuDCZ11e6EmMKyUGjpDzTIAZ2XxmyWUJ06yzEw7oLo8noiCE_Q"
  }''';

Wallet getTestWallet() {
  final walletJwk = json.decode(getWalletString);

  return Wallet.fromJwk(walletJwk);
}

Future<void> addTestFilesToDb(
  Database db, {
  required String driveId,
  required String rootFolderId,
  required String nestedFolderId,
  required int emptyNestedFolderCount,
  required String emptyNestedFolderIdPrefix,
  required int rootFolderFileCount,
  required int nestedFolderFileCount,
  int seed = 0,
}) async {
  await db.batch((batch) {
    // Default date
    final defaultDate = DateTime(2017, 9, 7, 17, 30);
    // Create fake drive for test
    batch.insert(
      db.drives,
      DrivesCompanion.insert(
        id: driveId,
        rootFolderId: rootFolderId,
        ownerAddress: 'fake-owner-address',
        name: 'fake-drive-name',
        privacy: DrivePrivacyTag.public,
      ),
    );
    // Create fake root folder for drive and sub folders
    batch.insertAll(
      db.folderEntries,
      [
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'fake-drive-name',
          isHidden: const Value(false),
          path: '',
        ),
        FolderEntriesCompanion.insert(
          id: nestedFolderId,
          driveId: driveId,
          parentFolderId: Value(rootFolderId),
          name: nestedFolderId,
          isHidden: const Value(false),
          path: '',
        ),
        ...List.generate(
          emptyNestedFolderCount,
          (i) {
            final folderId = '$emptyNestedFolderIdPrefix$i';
            return FolderEntriesCompanion.insert(
              id: folderId,
              driveId: driveId,
              parentFolderId: Value(rootFolderId),
              name: folderId,
              isHidden: const Value(false),
              path: '',
            );
          },
        )..shuffle(Random(0)),
      ],
    );
    // Insert fake files
    batch.insertAll(
      db.fileEntries,
      [
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: rootFolderId,
              name: fileId,
              dataTxId: '${fileId}Data',
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
              path: '',
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: nestedFolderId,
              name: fileId,
              dataTxId: '${fileId}Data',
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
              path: '',
            );
          },
        )..shuffle(Random(0)),
      ],
    );
    // Insert fake file revisions
    batch.insertAll(
      db.fileRevisions,
      [
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return FileRevisionsCompanion.insert(
              fileId: fileId,
              driveId: driveId,
              parentFolderId: rootFolderId,
              name: fileId,
              metadataTxId: '${fileId}Meta',
              action: RevisionAction.create,
              dataTxId: '${fileId}Data',
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return FileRevisionsCompanion.insert(
              fileId: fileId,
              driveId: driveId,
              parentFolderId: nestedFolderId,
              name: fileId,
              dataTxId: '${fileId}Meta',
              metadataTxId: '${fileId}Data',
              action: RevisionAction.create,
              size: 500,
              dateCreated: Value(defaultDate),
              lastModifiedDate: defaultDate,
              dataContentType: const Value(''),
              isHidden: const Value(false),
            );
          },
        )..shuffle(Random(0)),
      ],
    );
    // Insert fake metadata and data transactions
    batch.insertAll(
      db.networkTransactions,
      [
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Meta',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          rootFolderFileCount,
          (i) {
            final fileId = '$rootFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Data',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Meta',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
        ...List.generate(
          nestedFolderFileCount,
          (i) {
            final fileId = '$nestedFolderId$i';
            return NetworkTransactionsCompanion.insert(
              id: '${fileId}Data',
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(defaultDate),
            );
          },
        )..shuffle(Random(0)),
      ],
    );
  });
}

Future<Transaction> getTestTransaction(String path) async =>
    Transaction.fromJson(json.decode(await File(path).readAsString()));

Future<DataItem> getTestDataItem(String path) async {
  final wallet = getTestWallet();
  final dataItem = DataItem.withJsonData(
    owner: await wallet.getOwner(),
    data: json.decode(await File(path).readAsString()),
  );
  await dataItem.sign(ArweaveSigner(getTestWallet()));
  return dataItem;
}

User getTestUser() => User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: 'test-wallet-address',
      walletBalance: BigInt.from(1000),
      cipherKey: SecretKey([1, 2, 3, 4, 5]),
      profileType: ProfileType.arConnect,
      ioTokens: '100',
      errorFetchingIOTokens: false,
    );
