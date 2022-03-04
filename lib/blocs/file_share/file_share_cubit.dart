import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

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
    final file =
        await _driveDao.fileById(driveId: driveId, fileId: fileId).getSingle();

    late Uri fileShareLink;
    SecretKey? fileKey;

    if (drive.isPrivate) {
      final profile = _profileCubit.state as ProfileLoggedIn;
      fileKey = await _driveDao.getFileKey(driveId, fileId, profile.cipherKey);
      if (fileKey != null) {
        fileShareLink = await generatePrivateFileShareLink(
          fileId: file.id,
          fileKey: fileKey,
        );
      } else {
        throw StateError('File key not found');
      }
    } else {
      fileShareLink = generatePublicFileShareLink(fileId: file.id);
    }

    emit(
      FileShareLoadSuccess(
        fileName: file.name,
        fileShareLink: fileShareLink,
        isPublicFile: drive.isPublic,
      ),
    );
  }
}
