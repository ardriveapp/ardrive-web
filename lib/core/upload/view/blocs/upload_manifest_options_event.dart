part of 'upload_manifest_options_bloc.dart';

sealed class UploadManifestOptionsEvent extends Equatable {
  const UploadManifestOptionsEvent();

  @override
  List<Object> get props => [];
}

final class SelectManifest extends UploadManifestOptionsEvent {
  final FileEntry manifest;

  const SelectManifest({required this.manifest});

  @override
  List<Object> get props => [manifest];
}

final class DeselectManifest extends UploadManifestOptionsEvent {
  final FileEntry manifest;

  const DeselectManifest({required this.manifest});
}
