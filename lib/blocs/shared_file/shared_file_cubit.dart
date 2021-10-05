import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'shared_file_state.dart';

/// [SharedFileCubit] includes logic for displaying a file shared with another user.
class SharedFileCubit extends Cubit<SharedFileState> {
  final String? fileId;

  /// The [SecretKey] that can be used to decode the target file.
  ///
  /// `null` if the file is public.
  final SecretKey? fileKey;

  final ArweaveService? _arweave;

  SharedFileCubit({this.fileId, this.fileKey, ArweaveService? arweave})
      : _arweave = arweave,
        super(SharedFileLoadInProgress()) {
    loadFileDetails();
  }

  Future<void> loadFileDetails() async {
    emit(SharedFileLoadInProgress());

    final file = await _arweave!.getLatestFileEntityWithId(fileId!, fileKey);

    if (file != null) {
      emit(SharedFileLoadSuccess(file: file, fileKey: fileKey));
    } else {
      emit(SharedFileNotFound());
    }
  }
}
