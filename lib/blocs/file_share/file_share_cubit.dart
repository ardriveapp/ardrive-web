import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

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

    final profile = _profileCubit.state as ProfileLoaded;

    final file = await _driveDao.getFileById(driveId, fileId);
    final fileKey =
        await _driveDao.getFileKey(driveId, fileId, profile.cipherKey);
    final fileKeyBase64 = utils.encodeBytesToBase64(await fileKey.extract());

    emit(
      FileShareLoadSuccess(
        fileName: file.name,
        fileShareLink: Uri.parse(
            'https://app.ardrive.io/#/file/${file.id}/view?fileKey=$fileKeyBase64'),
        isPublicFile: fileKey == null,
      ),
    );
  }
}
