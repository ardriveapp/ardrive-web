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

final class ShowArNSSelection extends UploadManifestOptionsEvent {
  final FileEntry manifest;

  const ShowArNSSelection({required this.manifest});
}

final class HideArNSSelection extends UploadManifestOptionsEvent {
  final FileEntry manifest;

  const HideArNSSelection({required this.manifest});
}

final class LinkManifestToUndername extends UploadManifestOptionsEvent {
  final FileEntry manifest;
  final ANTRecord antRecord;
  final ARNSUndername? undername;

  const LinkManifestToUndername({
    required this.manifest,
    required this.antRecord,
    required this.undername,
  });
}

final class LoadAnts extends UploadManifestOptionsEvent {}
