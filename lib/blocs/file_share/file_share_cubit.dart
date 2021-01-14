import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';

part 'file_share_state.dart';

/// [FileShareCubit] includes logic for the user to retrieve a link to share a public/private file with.
class FileShareCubit extends Cubit<FileShareState> {
  final String driveId;
  final String fileId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  FileShareCubit({
    @required this.driveId,
    @required this.fileId,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(FileShareLoadInProgress()) {
    loadFileShareDetails();
  }
  Future<void> loadFileShareDetails() async {
    emit(FileShareLoadInProgress());

    final drive = await _driveDao.driveById(driveId).getSingle();
    final file = await _driveDao.fileById(driveId, fileId).getSingle();

    final isPublicFile = drive.isPublic;

    // On web, link to the current origin the user is on.
    // Elsewhere, link to app.ardrive.io.
    final linkOrigin = kIsWeb ? Uri.base.origin : 'https://app.ardrive.io';
    var fileShareLink = '$linkOrigin/#/file/${file.id}/view';

    if (!isPublicFile) {
      final profile = _profileCubit.state as ProfileLoggedIn;

      final fileKey =
          await _driveDao.getFileKey(driveId, fileId, profile.cipherKey);
      final fileKeyBase64 =
          utils.encodeBytesToBase64(await fileKey.extractBytes());

      fileShareLink = fileShareLink + '?fileKey=$fileKeyBase64';
    }

    emit(
      FileShareLoadSuccess(
        fileName: file.name,
        fileShareLink: Uri.parse(fileShareLink),
        isPublicFile: isPublicFile,
      ),
    );
  }
}
