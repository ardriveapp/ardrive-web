import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for PE-9200 / F1: the share page's Download buttons used
/// `revisions.last`, which is the OLDEST revision, because the revision lists
/// handed to [DetailsPanel] are newest-first (see
/// `SharedFileCubit.computeRevisionsFromEntities`, which reverses the
/// chronologically sorted list). Recipients of an updated file saw the current
/// name in the header but silently downloaded the original bytes.
void main() {
  FileRevision revision({
    required String name,
    required String dataTxId,
    required int size,
    required DateTime dateCreated,
    required String action,
  }) {
    return FileRevision(
      fileId: 'file-id',
      driveId: 'drive-id',
      name: name,
      parentFolderId: 'parent-folder-id',
      size: size,
      lastModifiedDate: dateCreated,
      metadataTxId: 'metadata-$dataTxId',
      dataTxId: dataTxId,
      dateCreated: dateCreated,
      action: action,
      isHidden: false,
    );
  }

  final newest = revision(
    name: 'contract-signed.pdf',
    dataTxId: 'data-tx-newest',
    size: 300,
    dateCreated: DateTime.utc(2024, 3, 3),
    action: RevisionAction.uploadNewVersion,
  );
  final middle = revision(
    name: 'contract-reviewed.pdf',
    dataTxId: 'data-tx-middle',
    size: 200,
    dateCreated: DateTime.utc(2024, 2, 2),
    action: RevisionAction.uploadNewVersion,
  );
  final oldest = revision(
    name: 'contract-draft.pdf',
    dataTxId: 'data-tx-oldest',
    size: 100,
    dateCreated: DateTime.utc(2024, 1, 1),
    action: RevisionAction.create,
  );

  group('latestRevision', () {
    test('returns the newest revision of a newest-first list', () {
      final revisions = [newest, middle, oldest];

      expect(revisions.latestRevision, newest);
      expect(revisions.latestRevision.dataTxId, 'data-tx-newest');
      expect(revisions.latestRevision.name, 'contract-signed.pdf');
    });

    test('does not return the trailing (oldest) revision', () {
      final revisions = [newest, middle, oldest];

      expect(revisions.latestRevision, isNot(revisions.last));
      expect(revisions.last, oldest);
    });

    test('returns the only revision when the file was never updated', () {
      final revisions = [oldest];

      expect(revisions.latestRevision, oldest);
    });
  });

  group('shared file download', () {
    test('hands the newest revision to the download prompt', () {
      final revisions = [newest, middle, oldest];

      // Mirrors what both share-page Download buttons build before calling
      // `promptToDownloadSharedFile`.
      final file =
          ARFSFactory().getARFSFileFromFileRevision(revisions.latestRevision);

      expect(file.dataTxId, 'data-tx-newest');
      expect(file.name, 'contract-signed.pdf');
      expect(file.size, 300);
      expect(file.txId, 'metadata-data-tx-newest');
    });
  });
}
