import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/markdown/upload_markdown_state.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/markdown/domain/markdown_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UploadMarkdownCubit extends Cubit<UploadMarkdownState> {
  late FolderNode rootFolderNode;

  final ProfileCubit _profileCubit;
  final Drive _drive;

  final MarkdownRepository _markdownRepository;

  final ArDriveAuth _auth;

  final String _markdownText;
  final FolderEntry _parentFolderEntry;
  final String _markdownFilename;

  UploadMarkdownCubit({
    required ProfileCubit profileCubit,
    required Drive drive,
    required MarkdownRepository markdownRepository,
    required ArDriveAuth auth,
    required String markdownText,
    required String markdownFilename,
    required FolderEntry parentFolderEntry,
  })  : _drive = drive,
        _profileCubit = profileCubit,
        _markdownRepository = markdownRepository,
        _auth = auth,
        _markdownText = markdownText,
        _parentFolderEntry = parentFolderEntry,
        _markdownFilename = markdownFilename,
        super(UploadMarkdownInitial(
            markdownFilename: markdownFilename,
            parentFolderEntry: parentFolderEntry)) {}

  void selectUploadMethod(
      UploadMethod method, UploadPaymentMethodInfo info, bool canUpload) {
    if (state is MarkdownUploadReview) {
      emit(
        (state as MarkdownUploadReview).copyWith(
          uploadMethod: method,
          canUpload: canUpload,
          freeUpload: info.isFreeThanksToTurbo,
        ),
      );
    }
  }

  /// User has confirmed that they would like to submit a markdown revision transaction
  Future<void> confirmRevision(
    String filename,
  ) async {
    final revisionConfirmationState = state as UploadMarkdownRevisionConfirm;
    final parentFolder = revisionConfirmationState.parentFolderEntry;
    final existingMarkdownFileId =
        revisionConfirmationState.existingMarkdownFileId;

    emit(UploadMarkdownPreparingFile(parentFolderEntry: parentFolder));
    await prepareMarkdownTx(
        existingMarkdownFileId: existingMarkdownFileId,
        markdownFilename: filename,
        markdownText: _markdownText);
  }

  /// User selected a new name due to name conflict, confirm that form is valid and check for conflicts again
  Future<void> recheckConflicts(String name) async {
    final conflictState = (state as UploadMarkdownNameConflict);
    final parentFolder = conflictState.parentFolderEntry;
    final conflictingName = conflictState.conflictingName;

    if (name == conflictingName) {
      return;
    }

    emit(UploadMarkdownCheckingForConflicts(parentFolderEntry: parentFolder));
    await checkNameConflicts(name);
  }

  Future<void> checkForConflicts(String name) async {
    /// Prevent multiple checks from being triggered
    if (state is! UploadMarkdownInitial) {
      return;
    }

    final parentFolder = (state as UploadMarkdownInitial).parentFolderEntry;

    emit(UploadMarkdownCheckingForConflicts(parentFolderEntry: parentFolder));
    await checkNameConflicts(name);
  }

  Future<void> checkNameConflicts(String name) async {
    final parentFolder =
        (state as UploadMarkdownCheckingForConflicts).parentFolderEntry;

    final conflictTuple =
        await _markdownRepository.checkNameConflictAndReturnExistingFileId(
      driveId: _drive.id,
      parentFolderId: parentFolder.id,
      name: name,
    );

    final hasConflictNames = conflictTuple.$1;
    final existingMarkdownFileId = conflictTuple.$2;

    if (hasConflictNames) {
      emit(UploadMarkdownNameConflict(
        conflictingName: name,
        parentFolderEntry: parentFolder,
      ));
      return;
    }

    final markdownRevisionId = existingMarkdownFileId;

    if (markdownRevisionId != null) {
      emit(
        UploadMarkdownRevisionConfirm(
          existingMarkdownFileId: markdownRevisionId,
          parentFolderEntry: parentFolder,
        ),
      );
      return;
    }

    emit(UploadMarkdownPreparingFile(parentFolderEntry: parentFolder));

    await prepareMarkdownTx(
        markdownFilename: name, markdownText: _markdownText);

    logger.d('No conflicts found');
  }

  Future<void> prepareMarkdownTx({
    FileID? existingMarkdownFileId,
    required String markdownFilename,
    required String markdownText,
  }) async {
    try {
      final parentFolder =
          (state as UploadMarkdownPreparingFile).parentFolderEntry;

      final markdownFile = await _markdownRepository.getMarkdownFile(
        markdownFilename: markdownFilename,
        markdownText: markdownText,
      );

      emit(
        MarkdownUploadReview(
          markdownSize: await markdownFile.length,
          markdownName: markdownFilename,
          markdownFile: markdownFile,
          drive: _drive,
          parentFolderEntry: parentFolder,
          existingMarkdownFileId: existingMarkdownFileId,
        ),
      );
    } catch (e) {
      logger.e('Failed to prepare markdown file', e);
      addError(e);
    }
  }

  Future<void> uploadMarkdown() async {
    if (await _profileCubit.logoutIfWalletMismatch()) {
      emit(UploadMarkdownWalletMismatch());
      return;
    }

    if (state is MarkdownUploadReview) {
      try {
        final createMarkdownUploadReview = state as MarkdownUploadReview;
        final uploadType =
            createMarkdownUploadReview.uploadMethod == UploadMethod.ar
                ? UploadType.d2n
                : UploadType.turbo;

        emit(MarkdownUploadInProgress());

        await _markdownRepository.uploadMarkdown(
          params: MarkdownUploadParams(
            markdownFile: createMarkdownUploadReview.markdownFile,
            driveId: _drive.id,
            parentFolderId: createMarkdownUploadReview.parentFolderEntry.id,
            existingMarkdownFileId:
                createMarkdownUploadReview.existingMarkdownFileId,
            uploadType: uploadType,
            wallet: _auth.currentUser.wallet,
          ),
        );

        emit(UploadMarkdownSuccess());
      } catch (e) {
        logger.e('An error occurred uploading the markdown file.', e);
        addError(e);
      }
    }
  }

  // TODO: excise?
  void backToName() {
    emit(UploadMarkdownInitial(
      markdownFilename: _markdownFilename,
      parentFolderEntry: _parentFolderEntry,
    ));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(UploadMarkdownFailure());
    super.onError(error, stackTrace);

    logger.e('Failed to create markdown file', error, stackTrace);
  }
}

class UploadMarkdownParams {
  final Transaction signedBundleTx;
  final Future<void> Function() addMarkdownToDatabase;

  UploadMarkdownParams({
    required this.signedBundleTx,
    required this.addMarkdownToDatabase,
  });
}
