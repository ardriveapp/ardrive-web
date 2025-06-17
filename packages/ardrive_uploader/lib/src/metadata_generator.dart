import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arfs/arfs.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// this class will get an `IOFile` and generate the metadata for it
///
/// `A` is the type of the arguments that will be passed to the generator
///
/// `T` is the type of the metadata that will be generated
abstract class UploadMetadataGenerator<T extends UploadMetadata, A> {
  Future<T> generateMetadata(IOEntity entity, {required A arguments});
}

abstract class TagsGenerator<T> {
  Map<String, List<Tag>> generateTags(T arguments);
}

/// This abstract class acts as an interface for all upload metadata generators
/// It expects an IOEntity (file or folder) and optional arguments to generate the metadata
abstract class ARFSDriveUploadMetadataGenerator {
  Future<ARFSUploadMetadata> generateDrive({
    required String name,
    required bool isPrivate,
  });
}

class ARFSUploadMetadataGenerator
    implements
        UploadMetadataGenerator<ARFSUploadMetadata, ARFSUploadMetadataArgs>,
        ARFSDriveUploadMetadataGenerator {
  ARFSUploadMetadataGenerator({
    required ARFSTagsGenetator tagsGenerator,
  }) : _tagsGenerator = tagsGenerator;

  final ARFSTagsGenetator _tagsGenerator;

  @override
  Future<ARFSUploadMetadata> generateMetadata(
    IOEntity entity, {
    required ARFSUploadMetadataArgs arguments,
  }) async {
    final String id;

    if (arguments.entityId != null) {
      id = arguments.entityId!;
    } else {
      id = const Uuid().v4();
    }

    final String contentType;

    if (arguments.isPrivate) {
      contentType = 'application/octet-stream';
    } else {
      if (entity is IOFile) {
        contentType = entity.contentType;
      } else {
        // folders and drives are always json
        contentType = 'application/json';
      }
    }

    if (entity is IOFile) {
      ARFSUploadMetadataArgsValidator.validate(arguments, EntityType.file);

      final file = entity;

      final tags = _tagsGenerator.generateTags(
        ARFSTagsArgs(
          driveId: arguments.driveId!,
          parentFolderId: arguments.parentFolderId,
          entityId: id,
          entity: EntityType.file,
          contentType: contentType,
          isPrivate: arguments.isPrivate,
          licenseDefinitionTxId: arguments.licenseDefinitionTxId,
          licenseAdditionalTags: arguments.licenseAdditionalTags?.entries
              .map((e) => Tag(e.key, e.value))
              .toList(),
          assignedName: arguments.assignedName,
        ),
      );

      return ARFSFileUploadMetadata(
        isPrivate: arguments.isPrivate,
        size: await file.length,
        lastModifiedDate: file.lastModifiedDate,
        dataContentType: file.contentType,
        driveId: arguments.driveId!,
        parentFolderId: arguments.parentFolderId!,
        name: file.name,
        id: id,
        licenseDefinitionTxId: arguments.licenseDefinitionTxId,
        licenseAdditionalTags: arguments.licenseAdditionalTags,
        assignedName: arguments.assignedName,
        fallbackTxId: arguments.fallbackTxId,
        paidBy: arguments.paidBy ?? [],
      )
        ..setDataTags(tags['data-item']!)
        ..setEntityMetadataTags(tags['entity']!);
    } else if (entity is IOFolder) {
      ARFSUploadMetadataArgsValidator.validate(arguments, EntityType.folder);

      final folder = entity;

      final tags = _tagsGenerator.generateTags(
        ARFSTagsArgs(
          driveId: arguments.driveId!,
          parentFolderId: arguments.parentFolderId,
          entityId: id,
          entity: EntityType.folder,
          contentType: contentType,
          isPrivate: arguments.isPrivate,
        ),
      );

      return ARFSFolderUploadMetatadata(
          id: id,
          isPrivate: arguments.isPrivate,
          driveId: arguments.driveId!,
          parentFolderId: arguments.parentFolderId,
          name: folder.name,
          paidBy: arguments.paidBy ?? [])
        ..setEntityMetadataTags(tags['entity']!);
    }

    throw Exception('Invalid file type');
  }

  /// We don't have a `IOEntity` for Drives. They are logical entities that are
  /// created by the user. So we need to generate the metadata for them
  /// manually.
  @override
  Future<ARFSUploadMetadata> generateDrive({
    required String name,
    required bool isPrivate,
  }) async {
    final id = const Uuid().v4();

    final String contentType;

    if (isPrivate) {
      contentType = 'application/octet-stream';
    } else {
      contentType = 'application/json';
    }

    final tags = _tagsGenerator.generateTags(
      ARFSTagsArgs(
        isPrivate: isPrivate,
        entityId: id,
        entity: EntityType.drive,
        contentType: contentType,
      ),
    );

    final uploadMetadata =
        ARFSDriveUploadMetadata(isPrivate: isPrivate, name: name, id: id)
          ..setEntityMetadataTags(tags['entity']!);

    return uploadMetadata;
  }
}

class ARFSUploadMetadataArgs extends Equatable {
  final String? driveId;
  final String? parentFolderId;
  final String? privacy;
  final bool isPrivate;
  final String? entityId;
  final UploadType type;
  final String? licenseDefinitionTxId;
  final Map<String, String>? licenseAdditionalTags;
  final String? assignedName;
  final String? fallbackTxId;
  final List<String>? paidBy;

  factory ARFSUploadMetadataArgs.file({
    required String driveId,
    required String parentFolderId,
    required bool isPrivate,
    required UploadType type,
    String? entityId,
    Map<String, String>? customBundleTags,
    String? assignedName,
    String? fallbackTxId,
    List<String>? paidBy,
  }) {
    return ARFSUploadMetadataArgs(
      driveId: driveId,
      parentFolderId: parentFolderId,
      isPrivate: isPrivate,
      entityId: entityId,
      type: type,
      assignedName: assignedName,
      fallbackTxId: fallbackTxId,
      paidBy: paidBy,
    );
  }

  factory ARFSUploadMetadataArgs.folder({
    required String driveId,
    required bool isPrivate,
    required UploadType type,
    required String path,
    String? parentFolderId,
    String? entityId,
    List<String>? paidBy,
  }) {
    return ARFSUploadMetadataArgs(
      driveId: driveId,
      isPrivate: isPrivate,
      entityId: entityId,
      parentFolderId: parentFolderId,
      type: type,
      paidBy: paidBy,
    );
  }

  factory ARFSUploadMetadataArgs.drive({
    required bool isPrivate,
    required UploadType type,
  }) {
    return ARFSUploadMetadataArgs(
      isPrivate: isPrivate,
      type: type,
    );
  }

  ARFSUploadMetadataArgs({
    required this.isPrivate,
    required this.type,
    this.driveId,
    this.parentFolderId,
    this.privacy,
    this.entityId,
    this.licenseDefinitionTxId,
    this.licenseAdditionalTags,
    this.assignedName,
    this.fallbackTxId,
    this.paidBy,
  });

  @override
  List<Object?> get props => [
        driveId,
        parentFolderId,
        isPrivate,
        type,
        entityId,
        licenseDefinitionTxId,
        licenseAdditionalTags,
        assignedName,
      ];
}

class ARFSTagsGenetator implements TagsGenerator<ARFSTagsArgs> {
  final AppInfoServices _appInfoServices;

  // constructor
  ARFSTagsGenetator({
    required AppInfoServices appInfoServices,
  }) : _appInfoServices = appInfoServices;

  @override
  Map<String, List<Tag>> generateTags(ARFSTagsArgs arguments) {
    final entityTags = _entityTags(arguments);

    final dataItemTags = [
      ...appTags(_appInfoServices),
      Tag(EntityTag.contentType, arguments.contentType),
      if (arguments.licenseDefinitionTxId != null) ...[
        Tag(LicenseTag.licenseDefinitionTxId, arguments.licenseDefinitionTxId!),
        if (arguments.licenseAdditionalTags != null)
          ...arguments.licenseAdditionalTags!
      ],
    ];

    final entityMedataTags = [...entityTags, ...appTags(_appInfoServices)];

    return {
      'data-item': dataItemTags,
      'entity': entityMedataTags,
    };
  }

  List<Tag> _entityTags(
    ARFSTagsArgs arguments,
  ) {
    ARFSTagsValidator.validate(arguments);

    final List<Tag> tags = [];

    final driveId = Tag(EntityTag.driveId, arguments.driveId!);

    tags.add(driveId);

    final appInfo = _appInfoServices.appInfo;

    final String contentType;

    if (arguments.isPrivate!) {
      contentType = 'application/octet-stream';
    } else {
      contentType = 'application/json';
    }

    tags.add(Tag(EntityTag.contentType, contentType));

    tags.add(Tag(EntityTag.arFs, appInfo.arfsVersion));

    switch (arguments.entity) {
      case EntityType.file:
        tags.add(Tag(EntityTag.fileId, arguments.entityId!));
        tags.add(Tag(EntityTag.entityType, EntityTypeTag.file));
        tags.add(Tag(EntityTag.parentFolderId, arguments.parentFolderId!));

        if (arguments.assignedName != null) {
          tags.add(Tag(EntityTag.arnsName, arguments.assignedName!));
        }

        break;
      case EntityType.folder:
        tags.add(Tag(EntityTag.folderId, arguments.entityId!));
        tags.add(Tag(EntityTag.entityType, EntityType.folder.name));

        if (arguments.parentFolderId != null) {
          tags.add(Tag(EntityTag.parentFolderId, arguments.parentFolderId!));
        }

        break;
      case EntityType.drive:
        if (arguments.isPrivate ?? false) {
          tags.add(Tag(EntityTag.drivePrivacy, 'private'));
        } else {
          tags.add(Tag(EntityTag.drivePrivacy, 'public'));
        }

        tags.add(Tag(EntityTag.entityType, EntityType.drive.name));

        break;
    }

    return tags;
  }
}

class ARFSUploadMetadataArgsValidator {
  static void validate(ARFSUploadMetadataArgs args, EntityType entity) {
    switch (entity) {
      case EntityType.file:
        if (args.driveId == null) {
          throw ArgumentError('driveId must not be null');
        }
        if (args.parentFolderId == null) {
          throw ArgumentError('parentFolderId must not be null');
        }
        break;

      case EntityType.folder:
        if (args.driveId == null) {
          throw ArgumentError('driveId must not be null');
        }
        break;

      case EntityType.drive:
        if (args.privacy == null) {
          throw ArgumentError('privacy must not be null');
        }
        break;

      default:
        throw ArgumentError('Invalid EntityType');
    }
  }
}

class ARFSTagsValidator {
  static void validate(ARFSTagsArgs args) {
    if (args.driveId == null) {
      throw ArgumentError('driveId must not be null');
    }

    if (args.isPrivate == null) {
      throw ArgumentError('isPrivate must not be null');
    }

    switch (args.entity) {
      case EntityType.file:
        if (args.entityId == null) {
          throw ArgumentError('entityId must not be null');
        }
        if (args.parentFolderId == null) {
          throw ArgumentError('parentFolderId must not be null');
        }

        break;
      case EntityType.folder:
        if (args.entityId == null) {
          throw ArgumentError('entityId must not be null');
        }

        break;
      case EntityType.drive:
        if (args.isPrivate == null) {
          throw ArgumentError('privacy must not be null');
        }
        break;
    }
  }
}

class ARFSTagsArgs extends Equatable {
  final String? driveId;
  final String? parentFolderId;
  final String? entityId;
  final bool? isPrivate;
  final String contentType;
  final EntityType entity;
  final String? licenseDefinitionTxId;
  final List<Tag>? licenseAdditionalTags;
  final String? assignedName;

  ARFSTagsArgs({
    this.driveId,
    this.parentFolderId,
    this.isPrivate,
    this.entityId,
    required this.entity,
    required this.contentType,
    this.licenseDefinitionTxId,
    this.licenseAdditionalTags,
    this.assignedName,
  });

  @override
  List<Object?> get props => [
        driveId,
        parentFolderId,
        entityId,
        isPrivate,
        contentType,
        entity,
        licenseDefinitionTxId,
        licenseAdditionalTags,
        assignedName,
      ];
}
