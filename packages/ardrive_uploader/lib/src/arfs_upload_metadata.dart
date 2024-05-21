import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

abstract class UploadMetadata {}

class ARFSDriveUploadMetadata extends ARFSUploadMetadata {
  ARFSDriveUploadMetadata({
    required super.name,
    required super.id,
    required super.isPrivate,
  });

  // TODO: implement toJson
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError();
  }
}

class ARFSFolderUploadMetatadata extends ARFSUploadMetadata {
  final String driveId;
  final String? parentFolderId;

  ARFSFolderUploadMetatadata({
    required this.driveId,
    this.parentFolderId,
    required super.name,
    required super.id,
    required super.isPrivate,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }
}

class ARFSFileUploadMetadata extends ARFSUploadMetadata {
  ARFSFileUploadMetadata({
    required this.size,
    required this.lastModifiedDate,
    required this.dataContentType,
    required this.driveId,
    required this.parentFolderId,
    this.licenseDefinitionTxId,
    this.licenseAdditionalTags,
    required super.name,
    required super.id,
    required super.isPrivate,
  });

  final int size;
  final DateTime lastModifiedDate;
  final String dataContentType;
  final String driveId;
  final String parentFolderId;
  final String? licenseDefinitionTxId;
  final Map<String, String>? licenseAdditionalTags;

  late List<Tag> _dataTags;

  void setDataTags(List<Tag> dataTags) => _dataTags = dataTags;

  String? _dataTxId;

  set setDataTxId(String dataTxId) => _dataTxId = dataTxId;

  String? get dataTxId => _dataTxId;

  String? _licenseTxId;

  set setLicenseTxId(String licenseTxId) => _licenseTxId = licenseTxId;

  String? get licenseTxId => _licenseTxId;

  Tag? _dataCipherTag;
  Tag? _dataCipherIvTag;

  void setDataCipher({
    required String cipher,
    required String cipherIv,
  }) {
    _dataCipherTag = Tag(
      EntityTag.cipher,
      cipher,
    );
    _dataCipherIvTag = Tag(
      EntityTag.cipherIv,
      cipherIv,
    );
  }

  List<Tag> getDataTags() {
    return [
      ..._dataTags,
      if (_dataCipherTag != null) _dataCipherTag!,
      if (_dataCipherIvTag != null) _dataCipherIvTag!,
    ];
  }

  @override
  Map<String, dynamic> toJson() {
    if (_dataTxId == null) {
      throw StateError('dataTxId is required but not set.');
    }

    return {
      'name': name,
      'size': size,
      'lastModifiedDate': lastModifiedDate.millisecondsSinceEpoch,
      'dataContentType': dataContentType,
      'dataTxId': dataTxId,
    }..addAll(licenseTxId != null
        ? {
            'licenseTxId': licenseTxId,
          }
        : {});
  }
}

abstract class ARFSUploadMetadata extends UploadMetadata {
  ARFSUploadMetadata({
    required this.name,
    required this.id,
    required this.isPrivate,
  });

  final String id;
  final String name;
  final bool isPrivate;

  String? _metadataTxId;

  late List<Tag> _entityMetadataTags;

  Tag? _cipherTag;
  Tag? _cipherIvTag;

  List<Tag> getEntityMetadataTags() {
    return [
      ..._entityMetadataTags,
      if (_cipherTag != null) _cipherTag!,
      if (_cipherIvTag != null) _cipherIvTag!,
    ];
  }

  void setEntityMetadataTags(List<Tag> entityMetadataTags) =>
      _entityMetadataTags = entityMetadataTags;

  void setCipher({
    required String cipher,
    required String cipherIv,
  }) {
    _cipherTag = Tag(
      EntityTag.cipher,
      cipher,
    );
    _cipherIvTag = Tag(
      EntityTag.cipherIv,
      cipherIv,
    );
  }

  set setMetadataTxId(String metadataTxId) => _metadataTxId = metadataTxId;
  String? get metadataTxId => _metadataTxId;

  Map<String, dynamic> toJson();

  @override
  String toString() => 'ARFSUploadMetadata: $name';
}
