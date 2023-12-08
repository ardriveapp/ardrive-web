import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:json_annotation/json_annotation.dart';

part 'plausible_custom_event_properties.g.dart';

@JsonSerializable()
class AppLoadedProperties {
  @JsonKey(name: 'App Version')
  String appVersion;
  @JsonKey(name: 'Platform')
  String platform;
  @JsonKey(name: 'Platform Version')
  String platformVersion;

  AppLoadedProperties({
    required this.appVersion,
    required this.platform,
    required this.platformVersion,
  });

  factory AppLoadedProperties.fromJson(Map<String, dynamic> json) =>
      _$AppLoadedPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$AppLoadedPropertiesToJson(this);
}

@JsonSerializable()
class NewButtonProperties {
  @JsonKey(name: 'Location')
  NewButtonLocation location;

  NewButtonProperties({
    required this.location,
  });

  factory NewButtonProperties.fromJson(Map<String, dynamic> json) =>
      _$NewButtonPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$NewButtonPropertiesToJson(this);
}

@JsonSerializable()
class UploadReviewProperties {
  @JsonKey(
    name: 'Drive Privacy',
  )
  DrivePrivacy drivePrivacy;
  @JsonKey(
    name: 'Upload Type',
  )
  UploadType uploadType;
  @JsonKey(name: 'Drag n Drop')
  bool dragNDrop;

  @JsonKey(name: 'Has Folders')
  bool hasFolders;
  @JsonKey(name: 'Single File')
  bool hasSingleFile;
  @JsonKey(name: 'Multiple Files')
  bool hasMultipleFiles;

  UploadReviewProperties({
    required this.drivePrivacy,
    required this.uploadType,
    required this.dragNDrop,
    required this.hasFolders,
    required this.hasSingleFile,
    required this.hasMultipleFiles,
  });

  factory UploadReviewProperties.fromJson(Map<String, dynamic> json) =>
      _$UploadReviewPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$UploadReviewPropertiesToJson(this);
}

enum NewButtonLocation {
  bottom,
  sidebar,
}

@JsonSerializable()
class LoginProperties {
  @JsonKey(
    name: 'Login Type',
  )
  final LoginType type;

  LoginProperties({
    required this.type,
  });

  factory LoginProperties.fromJson(Map<String, dynamic> json) =>
      _$LoginPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$LoginPropertiesToJson(this);
}

enum LoginType {
  arConnect,
  json,
  seedphrase,
}

@JsonSerializable()
class ResyncProperties {
  @JsonKey(
    name: 'Resync Type',
  )
  final ResyncType type;

  ResyncProperties({
    required this.type,
  });

  factory ResyncProperties.fromJson(Map<String, dynamic> json) =>
      _$ResyncPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$ResyncPropertiesToJson(this);
}

enum ResyncType {
  deepResync,
  resync,
}

@JsonSerializable()
class DriveCreationProperties {
  @JsonKey(
    name: 'Drive Privacy',
  )
  final DrivePrivacy drivePrivacy;

  DriveCreationProperties({
    required this.drivePrivacy,
  });

  factory DriveCreationProperties.fromJson(Map<String, dynamic> json) =>
      _$DriveCreationPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$DriveCreationPropertiesToJson(this);
}

@JsonSerializable()
class FolderCreationProperties {
  @JsonKey(
    name: 'Drive Privacy',
  )
  final DrivePrivacy drivePrivacy;

  FolderCreationProperties({
    required this.drivePrivacy,
  });

  factory FolderCreationProperties.fromJson(Map<String, dynamic> json) =>
      _$FolderCreationPropertiesFromJson(json);

  Map<String, dynamic> toJson() => _$FolderCreationPropertiesToJson(this);
}

@JsonSerializable()
class PinCreationProperties {
  @JsonKey(
    name: 'Drive Privacy',
  )
  final DrivePrivacy drivePrivacy;

  PinCreationProperties({
    required this.drivePrivacy,
  });

  factory PinCreationProperties.fromJson(Map<String, dynamic> json) =>
      _$PinCreationPropertiesFromJson(json);

  Map<String, dynamic> toJson() => _$PinCreationPropertiesToJson(this);
}

@JsonSerializable()
class SnapshotCreationProperties {
  @JsonKey(
    name: 'Drive Privacy',
  )
  final DrivePrivacy drivePrivacy;

  SnapshotCreationProperties({
    required this.drivePrivacy,
  });

  factory SnapshotCreationProperties.fromJson(Map<String, dynamic> json) =>
      _$SnapshotCreationPropertiesFromJson(json);

  Map<String, dynamic> toJson() => _$SnapshotCreationPropertiesToJson(this);
}

@JsonSerializable()
class AttachDriveProperties {
  @JsonKey(
    name: 'Drive Privacy',
  )
  final DrivePrivacy drivePrivacy;

  AttachDriveProperties({
    required this.drivePrivacy,
  });

  factory AttachDriveProperties.fromJson(Map<String, dynamic> json) =>
      _$AttachDrivePropertiesFromJson(json);

  Map<String, dynamic> toJson() => _$AttachDrivePropertiesToJson(this);
}
