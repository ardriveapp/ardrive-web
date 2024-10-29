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
  final Set<String> showingArNSSelection;
  final List<ANTRecord>? ants;
  final Map<String, List<String>> reservedNames;
  final bool arnsNamesLoaded;

  const UploadManifestOptionsReady({
    required this.manifestFiles,
    required this.selectedManifestIds,
    required this.showingArNSSelection,
    required this.ants,
    required this.reservedNames,
    required this.arnsNamesLoaded,
  });

  @override
  List<Object?> get props => [
        manifestFiles,
        selectedManifestIds,
        showingArNSSelection,
        ants,
        reservedNames,
      ];
}
