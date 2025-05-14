import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_share_state.dart';

/// [FileShareCubit] includes logic for the user to retrieve a link to share a public/private file with.
class FileShareCubit extends Cubit<FileShareState> {
  final String driveId;
  final String fileId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  FileShareCubit({
    required this.driveId,
    required this.fileId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(FileShareLoadInProgress()) {
    loadFileShareDetails();
  }
  Future<void> loadFileShareDetails() async {
    emit(FileShareLoadInProgress());

    final drive = await _driveDao.driveById(driveId: driveId).getSingle();

    final file = await _driveDao.fileById(fileId: fileId).getSingle();

    final dataTxStatus = (await (_driveDao.select(_driveDao.networkTransactions)
              ..where((entry) => entry.id.equals(file.dataTxId)))
            .getSingle())
        .status;

    if (dataTxStatus == TransactionStatus.failed) {
      emit(FileShareLoadedFailedFile());
      return;
    }

    late Uri fileShareLink;
    SecretKey? fileKey;

    switch (drive.privacy) {
      case DrivePrivacyTag.private:
        final profile = _profileCubit.state;
        DriveKey? driveKey;

        if (profile is ProfileLoggedIn) {
          driveKey =
              await _driveDao.getDriveKey(drive.id, profile.user.cipherKey);
        } else {
          driveKey = await _driveDao.getDriveKeyFromMemory(driveId);
        }

        if (driveKey == null) {
          throw StateError('Drive Key not found');
        }

        fileKey = await _driveDao.getFileKey(fileId, driveKey.key);

        fileShareLink = await generatePrivateFileShareLink(
          fileId: file.id,
          fileKey: fileKey,
        );

        break;
      case DrivePrivacyTag.public:
        fileShareLink = generatePublicFileShareLink(fileId: file.id);
        break;
      default:
    }

    emit(
      FileShareLoadSuccess(
        fileName: file.name,
        fileShareLink: fileShareLink,
        isPublicFile: drive.isPublic,
        isPending: dataTxStatus == TransactionStatus.pending,
      ),
    );
  }
}
