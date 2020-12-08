import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'shared_file_state.dart';

/// [SharedFileCubit] includes logic for displaying a file shared with another user.
class SharedFileCubit extends Cubit<SharedFileState> {
  final String fileId;

  final ArweaveService _arweave;

  SharedFileCubit({this.fileId, ArweaveService arweave})
      : _arweave = arweave,
        super(SharedFileLoadInProgress()) {
    loadFileDetails();
  }

  Future<void> loadFileDetails() async {
    emit(SharedFileLoadInProgress());

    final file = await _arweave.tryGetLatestFileEntityWithId(fileId);

    if (file != null) {
      emit(SharedFileLoadSuccess(file: file));
    } else {
      emit(SharedFileNotFound());
    }
  }
}
