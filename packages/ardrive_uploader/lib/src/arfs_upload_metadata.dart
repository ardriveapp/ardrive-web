import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

abstract class UploadMetadata {}

class ThumbnailUploadMetadata extends UploadMetadata {
  ThumbnailUploadMetadata({
    required this.size,
    required this.relatesTo,
    required this.height,
    required this.width,
    required this.name,
    required this.contentType,
    required this.originalFileId,
  });

  List<Tag> thumbnailTags() {
    final tags = <Tag>[
      Tag('Relates-To', relatesTo),
      Tag(EntityTag.contentType, contentType),
      Tag('Width', width.toString()),
      Tag('Height', height.toString()),
      Tag('Version', '1.0'),
      if (_cipherTag != null) Tag(EntityTag.cipher, _cipherTag!),
      if (_cipherIvTag != null) Tag(EntityTag.cipherIv, _cipherIvTag!),
    ];

    return tags;
  }

  final String relatesTo;
  final int size;
  final int height;
  final int width;
  final String name;
  final String contentType;
  final String originalFileId;
  String? _txId;
  String? _cipherTag;
  String? _cipherIvTag;

  set setTxId(String txId) => _txId = txId;

  setCipherTags({
    required String cipherTag,
    required String cipherIvTag,
  }) {
    _cipherTag = cipherTag;
    _cipherIvTag = cipherIvTag;
  }

  get txId => _txId;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'txId': _txId,
      'size': size,
      'height': height,
      'width': width,
    };
  }
}

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

/// Metadata for uploading a folder following the ARFS spec.
///
/// This metadata is used to create the metadata transaction for the folder.
class ARFSFolderUploadMetatadata extends ARFSUploadMetadata {
  /// The ID of the drive where the folder will be uploaded.
  final String driveId;

  /// The ID of the parent folder where the folder will be uploaded.
  final String? parentFolderId;

  ARFSFolderUploadMetatadata({
    required this.driveId,
    this.parentFolderId,
    required super.name,
    required super.id,
    required super.isPrivate,
  });

  /// Converts the metadata into a JSON object used on the metadata transaction.
  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }
}

/// A mixin that provides data-related functionality for uploading files.
mixin ARFSUploadData {
  /// The data tags for the file. These are the tags that will be added to the data transaction.
  List<Tag> _dataTags = [];

  /// The transaction ID for the data.
  String? _dataTxId;

  /// Gets the data transaction ID.
  String? get dataTxId => _dataTxId;

  /// Updates the data transaction ID.
  void updateDataTxId(String dataTxId) {
    _dataTxId = dataTxId;
  }

  /// The cipher tags for the data transaction.
  Tag? _dataCipherTag;
  Tag? _dataCipherIvTag;

  // Method to set data cipher tags
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

  // Setter for data tags
  void setDataTags(List<Tag> dataTags) => _dataTags = dataTags;

  /// Gets the data tags including cipher tags if set.
  ///
  /// Only call this method after setting the data tags and cipher tags if needed.
  List<Tag> getDataTags() {
    return [
      ..._dataTags,
      if (_dataCipherTag != null) _dataCipherTag!,
      if (_dataCipherIvTag != null) _dataCipherIvTag!,
    ];
  }
}

/// Metadata for uploading a file following the ARFS spec.
///
/// This metadata is used to create the metadata transaction for the file.
/// It also contains the data tags that will be added to the data transaction.
class ARFSFileUploadMetadata extends ARFSUploadMetadata with ARFSUploadData {
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
    this.assignedName,
    this.fallbackTxId,
    this.paidBy = const [],
  });

  final List<String> paidBy;

  /// The size of the file in bytes.
  final int size;

  /// The last modified date of the file.
  final DateTime lastModifiedDate;

  /// The content type of the file. e.g. 'image/jpeg'.
  final String dataContentType;

  /// The ID of the drive where the file will be uploaded.
  final String driveId;

  /// The ID of the parent folder where the file will be uploaded.
  final String parentFolderId;

  /// The transaction ID of the license definition.
  final String? licenseDefinitionTxId;

  /// Additional tags for the license.
  final Map<String, String>? licenseAdditionalTags;

  /// The transaction ID of the license transaction.
  String? _licenseTxId;

  // Getter for licenseTxId
  String? get licenseTxId => _licenseTxId;

  /// Additional Thumbnail tags for the file.
  List<ThumbnailUploadMetadata>? _thumbnailInfo;

  // Getter for thumbnailTxId
  List<ThumbnailUploadMetadata>? get thumbnailInfo => _thumbnailInfo;

  String? assignedName;

  final String? fallbackTxId;

  // Public method to set licenseTxId with validation or additional logic
  void updateLicenseTxId(String licenseTxId) {
    _licenseTxId = licenseTxId;
  }

  void updateThumbnailInfo(List<ThumbnailUploadMetadata> thumbnailInfo) {
    _thumbnailInfo = thumbnailInfo;
  }

  @override
  Map<String, dynamic> toJson() {
    if (dataTxId == null) {
      throw StateError('dataTxId is required but not set.');
    }

    return {
      'name': name,
      'size': size,
      'lastModifiedDate': lastModifiedDate.millisecondsSinceEpoch,
      'dataContentType': dataContentType,
      'dataTxId': dataTxId,
      if (_thumbnailInfo != null)
        'thumbnail': {
          'variants': [
            for (var variant in _thumbnailInfo!) variant.toJson(),
          ],
        },
      if (licenseTxId != null) 'licenseTxId': licenseTxId,
      if (assignedName != null) 'assignedNames': [assignedName!],
      if (fallbackTxId != null) 'fallbackTxId': fallbackTxId,
    };
  }
}

/// An abstract class that serves as a base for ARFS upload metadata.
///
/// This class provides common properties and methods for handling metadata
/// related to ARFS uploads, including the name, ID, and privacy status of the
/// entity, as well as methods for setting and retrieving entity metadata tags
/// and cipher tags.
abstract class ARFSUploadMetadata extends UploadMetadata {
  ARFSUploadMetadata({
    required this.name,
    required this.id,
    required this.isPrivate,
  });

  /// The unique identifier for the entity.
  final String id;

  /// The name of the entity.
  final String name;

  /// Boolean indicating if the entity is private.
  final bool isPrivate;

  /// The metadata transaction ID.
  String? _metadataTxId;

  /// List of entity metadata tags.
  late List<Tag> _entityMetadataTags;

  /// Tags for the cipher. It's null if the entity is not encrypted.
  Tag? _cipherTag;
  Tag? _cipherIvTag;

  /// Gets the entity metadata tags including cipher tags if set.
  List<Tag> getEntityMetadataTags() {
    return [
      ..._entityMetadataTags,
      if (_cipherTag != null) _cipherTag!,
      if (_cipherIvTag != null) _cipherIvTag!,
    ];
  }

  /// Sets the entity metadata tags.
  void setEntityMetadataTags(List<Tag> entityMetadataTags) =>
      _entityMetadataTags = entityMetadataTags;

  /// Sets the cipher and IV tags for the entity.
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

  /// Sets the metadata transaction ID.
  set setMetadataTxId(String metadataTxId) => _metadataTxId = metadataTxId;

  /// Gets the metadata transaction ID.
  String? get metadataTxId => _metadataTxId;

  /// Converts the metadata into a JSON object used on the metadata transaction.
  Map<String, dynamic> toJson();

  @override
  String toString() => 'ARFSUploadMetadata: $name';
}
