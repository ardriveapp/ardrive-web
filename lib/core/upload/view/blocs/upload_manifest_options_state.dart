part of 'upload_manifest_options_bloc.dart';

sealed class UploadManifestOptionsState extends Equatable {
  const UploadManifestOptionsState();

  @override
  List<Object?> get props => [];
}

final class UploadManifestOptionsInitial extends UploadManifestOptionsState {}

final class UploadManifestOptionsReady extends UploadManifestOptionsState {
  final Set<ManifestSelection> manifestFiles;
  final Set<String> selectedManifestIds;

  const UploadManifestOptionsReady({
    required this.manifestFiles,
    required this.selectedManifestIds,
  });

  @override
  List<Object?> get props => [
        manifestFiles,
        selectedManifestIds,
      ];
}
