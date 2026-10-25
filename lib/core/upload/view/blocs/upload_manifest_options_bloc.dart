import 'package:ardrive/models/models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'upload_manifest_options_event.dart';
part 'upload_manifest_options_state.dart';

/// Outputs the manifests selected to be updated with the upload.
class UploadManifestOptionsBloc
    extends Bloc<UploadManifestOptionsEvent, UploadManifestOptionsState> {
  final List<ManifestSelection> manifestFiles;
  final Set<String> _selectedManifestIds = {};

  UploadManifestOptionsBloc({
    required this.manifestFiles,
    List<String>? selectedManifestIds,
  }) : super(UploadManifestOptionsReady(
          manifestFiles: Set.from(manifestFiles),
          selectedManifestIds: Set.from(selectedManifestIds ?? []),
        )) {
    if (selectedManifestIds != null) {
      _selectedManifestIds.addAll(selectedManifestIds);
    }

    on<SelectManifest>((event, emit) async {
      _selectedManifestIds.add(event.manifest.id);
      emit(_createReadyState());
    });

    on<DeselectManifest>((event, emit) {
      _selectedManifestIds.remove(event.manifest.id);
      emit(_createReadyState());
    });
  }

  UploadManifestOptionsReady _createReadyState() {
    return UploadManifestOptionsReady(
      manifestFiles: Set.from(manifestFiles),
      selectedManifestIds: Set.from(_selectedManifestIds),
    );
  }
}

class ManifestSelection extends Equatable {
  final FileEntry manifest;

  const ManifestSelection({required this.manifest});

  @override
  List<Object?> get props => [manifest];
}
