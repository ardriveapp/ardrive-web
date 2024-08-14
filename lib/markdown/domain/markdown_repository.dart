import 'dart:async';
import 'dart:convert';

import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/markdown/domain/markdown_exceptions.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';

abstract class MarkdownRepository {
  /// Saves the markdown file to the database.
  Future<void> saveMarkdownToDatabase({
    required ARFSFileUploadMetadata markdownFileMetadata,
    String? existingMarkdownFileId,
  });

  Future<void> uploadMarkdown({
    required MarkdownUploadParams params,
  });

  Future<IOFile> getMarkdownFile({
    required String markdownFilename,
    required String markdownText,
  });

  // TODO: EntityId rather than FileId?
  /// Checks if there is a name conflict with the markdown file.
  /// Returns a tuple with the first value being a boolean indicating if there is a conflict. The second value is the existing markdown file id if there is a conflict.
  Future<(bool, String?)> checkNameConflictAndReturnExistingFileId({
    required String driveId,
    required String parentFolderId,
    required String name,
  });
}

class MarkdownRepositoryImpl implements MarkdownRepository {
  final DriveDao _driveDao;
  final ArDriveUploader _uploader;
  final FolderRepository _folderRepository;

  MarkdownRepositoryImpl(
    this._driveDao,
    this._uploader,
    this._folderRepository,
  );

  @override
  Future<void> saveMarkdownToDatabase({
    required ARFSFileUploadMetadata markdownFileMetadata,
    String? existingMarkdownFileId,
  }) async {
    try {
      final markdownFileEntity = FileEntity(
        size: markdownFileMetadata.size,
        parentFolderId: markdownFileMetadata.parentFolderId,
        name: markdownFileMetadata.name,
        lastModifiedDate: DateTime.now(),
        id: markdownFileMetadata.id,
        driveId: markdownFileMetadata.driveId,
        dataTxId: markdownFileMetadata.dataTxId,
        dataContentType: ContentType.markdown,
      );

      markdownFileEntity.txId = markdownFileMetadata.metadataTxId!;

      await _driveDao.runTransaction(
        () async {
          await _driveDao.writeFileEntity(markdownFileEntity);

          await _driveDao.insertFileRevision(
            markdownFileEntity.toRevisionCompanion(
              performedAction: existingMarkdownFileId == null
                  ? RevisionAction.create
                  : RevisionAction.uploadNewVersion,
            ),
          );
        },
      );
    } catch (e) {
      throw MarkdownCreationException(
        'Failed to save markdown file to database.',
        error: e,
      );
    }
  }

  @override
  Future<void> uploadMarkdown({
    required MarkdownUploadParams params,
  }) async {
    try {
      final completer = Completer<void>();

      final controller = await _uploader.upload(
        file: params.markdownFile,
        args: ARFSUploadMetadataArgs(
          driveId: params.driveId,
          parentFolderId: params.parentFolderId,
          entityId: params.existingMarkdownFileId,
          isPrivate: false,
          type: params.uploadType,
          privacy: DrivePrivacyTag.public,
        ),
        wallet: params.wallet,
        type: params.uploadType,
      );

      controller.onDone((tasks) {
        final task = tasks.first;
        final markdownFileMetadata =
            task.content!.first as ARFSFileUploadMetadata;

        saveMarkdownToDatabase(
          markdownFileMetadata: markdownFileMetadata,
          existingMarkdownFileId: params.existingMarkdownFileId,
        );

        completer.complete();
      });

      controller.onError((err) => completer.completeError(err));

      await completer.future;
    } catch (e) {
      throw MarkdownCreationException(
        'Failed to upload markdown.',
        error: e,
      );
    }
  }

  @override
  Future<IOFile> getMarkdownFile({
    required String markdownFilename,
    required String markdownText,
  }) async {
    try {
      final markdownFile = await IOFileAdapter().fromData(
        utf8.encode(markdownText),
        name: markdownFilename,
        lastModifiedDate: DateTime.now(),
        contentType: ContentType.markdown,
      );

      return markdownFile;
    } catch (e) {
      throw MarkdownCreationException(
        'Failed to create markdown file.',
        error: e,
      );
    }
  }

  @override
  Future<(bool, String?)> checkNameConflictAndReturnExistingFileId({
    required String driveId,
    required String parentFolderId,
    required String name,
  }) async {
    try {
      final foldersWithName = await _folderRepository.existingFoldersWithName(
          driveId: driveId, parentFolderId: parentFolderId, name: name);
      final filesWithName = await _folderRepository.existingFilesWithName(
          driveId: driveId, parentFolderId: parentFolderId, name: name);

      final conflictingFiles =
          filesWithName.where((e) => e.dataContentType != ContentType.markdown);

      if (foldersWithName.isNotEmpty || conflictingFiles.isNotEmpty) {
        // Name conflicts with existing file or folder
        // This is an error case, send user back to naming the markdown file
        return (true, null);
      }

      /// Might be a case where the user is trying to upload a new version of the markdown file
      final existingMarkdownFileId = filesWithName
          .firstWhereOrNull((e) => e.dataContentType == ContentType.markdown)
          ?.id;

      return (false, existingMarkdownFileId);
    } catch (e) {
      throw MarkdownCreationException(
        'Failed to check for name conflict.',
        error: e,
      );
    }
  }
}

class MarkdownUploadParams {
  final IOFile markdownFile;
  final String driveId;
  final String parentFolderId;
  final String? existingMarkdownFileId;
  final UploadType uploadType;
  final Wallet wallet;

  MarkdownUploadParams({
    required this.markdownFile,
    required this.driveId,
    required this.parentFolderId,
    required this.uploadType,
    this.existingMarkdownFileId,
    required this.wallet,
  });
}
