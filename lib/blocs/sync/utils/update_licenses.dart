part of 'package:ardrive/blocs/sync/sync_cubit.dart';

Future<void> _updateLicenses({
  required DriveDao driveDao,
  required ArweaveService arweave,
  required LicenseService licenseService,
  required List<FileRevision> revisionsToSyncLicense,
}) async {
  final licenseAssertionTxIds = revisionsToSyncLicense
      .where((rev) => rev.licenseTxId != rev.dataTxId)
      .map((e) => e.licenseTxId!)
      .toList();

  logger.d('Syncing ${licenseAssertionTxIds.length} license assertions');

  await for (final licenseAssertionTxsBatch
      in arweave.getLicenseAssertions(licenseAssertionTxIds)) {
    final licenseAssertionEntities = licenseAssertionTxsBatch
        .map((tx) => LicenseAssertionEntity.fromTransaction(tx));
    final licenseCompanions = licenseAssertionEntities.map((entity) {
      final revision = revisionsToSyncLicense.firstWhere(
        (rev) => rev.licenseTxId == entity.txId,
      );
      final licenseType =
          licenseService.licenseTypeByTxId(entity.licenseDefinitionTxId);
      return entity.toCompanion(
        fileId: revision.fileId,
        driveId: revision.driveId,
        licenseType: licenseType ?? LicenseType.unknown,
      );
    });

    logger
        .d('Inserting batch of ${licenseCompanions.length} license assertions');

    await driveDao.transaction(
      () async => {
        for (final licenseAssertionCompanion in licenseCompanions)
          {await driveDao.insertLicense(licenseAssertionCompanion)}
      },
    );
  }

  final licenseDataBundledTxIds = revisionsToSyncLicense
      .where((rev) => rev.licenseTxId == rev.dataTxId)
      .map((e) => e.licenseTxId!)
      .toList();

  logger.d('Syncing ${licenseAssertionTxIds.length} license-data bundles');

  await for (final licenseDataBundledTxsBatch
      in arweave.getLicenseDataBundled(licenseDataBundledTxIds)) {
    final licenseDataBundledEntities = licenseDataBundledTxsBatch
        .map((tx) => LicenseDataBundleEntity.fromTransaction(tx));
    final licenseCompanions = licenseDataBundledEntities.map((entity) {
      final revision = revisionsToSyncLicense.firstWhere(
        (rev) => rev.licenseTxId == entity.txId,
      );
      final licenseType =
          licenseService.licenseTypeByTxId(entity.licenseDefinitionTxId);
      return entity.toCompanion(
        fileId: revision.fileId,
        driveId: revision.driveId,
        licenseType: licenseType ?? LicenseType.unknown,
      );
    });

    logger.d(
        'Inserting batch of ${licenseCompanions.length} license-data bundles');

    await driveDao.transaction(
      () async => {
        for (final licenseAssertionCompanion in licenseCompanions)
          {await driveDao.insertLicense(licenseAssertionCompanion)}
      },
    );
  }
}
