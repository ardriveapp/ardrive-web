import 'dart:convert';

import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/utils/parse_assigned_names_from_string.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

/// Writes a file's names into its metadata, the public hint that visitors,
/// shared drives and the CLI read (docs/NAMES.md, "Where names are
/// recorded", Q6).
abstract class ArNSFileMetadataWriter {
  /// What one metadata revision costs in credits, in winc.
  Future<BigInt> estimateCost();

  /// Writes a new revision of the file with [names] as its `assignedNames`,
  /// unless it has them already. Returns whether it wrote.
  Future<bool> writeAssignedNames({
    required String driveId,
    required String fileId,
    required List<String> names,
  });
}

/// The ArDrive wallet as payer of name changes, and its credits.
abstract class ArNSPaymentSource {
  ArNSPayerSigner payer();

  /// The credits the wallet can spend, and the wallets that share theirs
  /// with it (sent as `x-paid-by`).
  Future<({BigInt balance, List<String> paidBy})> balance();
}

class ArDriveArNSPaymentSource implements ArNSPaymentSource {
  ArDriveArNSPaymentSource({
    required ArDriveAuth auth,
    required PaymentService paymentService,
  })  : _auth = auth,
        _paymentService = paymentService;

  final ArDriveAuth _auth;
  final PaymentService _paymentService;

  @override
  ArNSPayerSigner payer() => ArweaveWalletPayer(_auth.currentUser.wallet);

  @override
  Future<({BigInt balance, List<String> paidBy})> balance() async {
    try {
      final balance = await _paymentService.getBalanceAndPaidBy(
        wallet: _auth.currentUser.wallet,
      );
      return (balance: balance.balance, paidBy: balance.paidBy);
    } on TurboUserNotFound {
      return (balance: BigInt.zero, paidBy: const <String>[]);
    }
  }
}

/// The way a rename or a move writes file metadata: a data item through
/// Turbo, or a transaction where Turbo uploads are off.
class DriveDaoArNSFileMetadataWriter implements ArNSFileMetadataWriter {
  DriveDaoArNSFileMetadataWriter({
    required DriveDao driveDao,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required PaymentService paymentService,
    required ArDriveAuth auth,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        _turbo = turboUploadService,
        _paymentService = paymentService,
        _auth = auth;

  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final TurboUploadService _turbo;
  final PaymentService _paymentService;
  final ArDriveAuth _auth;

  /// A metadata revision with its tags and signature is about 2 KiB; priced
  /// at twice that, so the cost line never undersells it.
  static const _estimatedBytes = 4096;

  @override
  Future<BigInt> estimateCost() =>
      _paymentService.getPriceForBytes(byteSize: _estimatedBytes);

  @override
  Future<bool> writeAssignedNames({
    required String driveId,
    required String fileId,
    required List<String> names,
  }) async {
    // Names go on public files only (docs/NAMES.md, Q5).
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();
    if (drive.privacy != DrivePrivacyTag.public) return false;

    final wallet = _auth.currentUser.wallet;
    var wrote = false;
    await _driveDao.transaction(() async {
      final file = await _driveDao.fileById(fileId: fileId).getSingle();
      final current = parseAssignedNamesFromString(file.assignedNames) ?? [];
      if (const ListEquality<String>().equals(current, names)) return;

      final updated = file.copyWith(
        // An empty list says the names were removed; no list says nothing.
        assignedNames: Value(jsonEncode({'assignedNames': names})),
        lastUpdated: DateTime.now(),
      );
      final entity = updated.asEntity();

      if (_turbo.useTurboUpload) {
        final item = await _arweave.prepareEntityDataItem(entity, wallet);
        await _turbo.postDataItem(dataItem: item, wallet: wallet);
        entity.txId = item.id;
      } else {
        final tx = await _arweave.prepareEntityTx(entity, wallet, null);
        await _arweave.postTx(tx);
        entity.txId = tx.id;
      }

      await _driveDao.writeToFile(updated);
      await _driveDao.insertFileRevision(entity.toRevisionCompanion(
        performedAction: RevisionAction.assignName,
      ));
      wrote = true;
    });
    return wrote;
  }
}
