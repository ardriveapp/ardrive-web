import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/src/arfs_upload_metadata.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arfs/arfs.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

/// this class will get an `IOFile` and generate the metadata for it
///
/// `A` is the type of the arguments that will be passed to the generator
///
/// `T` is the type of the metadata that will be generated
abstract class UploadMetadataGenerator<T extends UploadMetadata, A> {
  Future<T> generateMetadata(IOEntity entity, [A arguments]);
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
  Future<ARFSUploadMetadata> generateMetadata(IOEntity entity,
      [ARFSUploadMetadataArgs? arguments]) async {
    if (arguments == null) {
      throw ArgumentError('arguments must not be null');
    }

    String id;
    if (arguments.entityId != null) {
      id = arguments.entityId!;
      print('reusing id: $id');
    } else {
      id = const Uuid().v4();
    }

    String contentType;

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
        entityMetadataTags: tags['entity']!,
        dataItemTags: tags['data-item']!,
        bundleTags: tags['bundle-data-item']!,
      );
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
        entityMetadataTags: tags['entity']!,
        dataItemTags: tags['data-item']!,
        bundleTags: tags['bundle-data-item']!,
      );
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

    String contentType;

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

    return ARFSDriveUploadMetadata(
      isPrivate: isPrivate,
      name: name,
      entityMetadataTags: tags['entity']!,
      dataItemTags: tags['data-item']!,
      bundleTags: tags['bundle-data-item']!,
      id: id,
    );
  }
}

class ARFSUploadMetadataArgs {
  final String? driveId;
  final String? parentFolderId;
  final String? privacy;
  final bool isPrivate;
  final String? entityId;

  factory ARFSUploadMetadataArgs.file({
    required String driveId,
    required String parentFolderId,
    required bool isPrivate,
    String? entityId,
  }) {
    return ARFSUploadMetadataArgs(
      driveId: driveId,
      parentFolderId: parentFolderId,
      isPrivate: isPrivate,
      entityId: entityId,
    );
  }

  factory ARFSUploadMetadataArgs.folder({
    required String driveId,
    required bool isPrivate,
    String? parentFolderId,
    String? entityId,
  }) {
    return ARFSUploadMetadataArgs(
      driveId: driveId,
      isPrivate: isPrivate,
      entityId: entityId,
      parentFolderId: parentFolderId,
    );
  }

  factory ARFSUploadMetadataArgs.drive({
    required bool isPrivate,
  }) {
    return ARFSUploadMetadataArgs(
      isPrivate: isPrivate,
    );
  }

  ARFSUploadMetadataArgs({
    required this.isPrivate,
    this.driveId,
    this.parentFolderId,
    this.privacy,
    this.entityId,
  });
}

class ARFSTagsGenetator implements TagsGenerator<ARFSTagsArgs> {
  final AppInfoServices _appInfoServices;

  // constructor
  ARFSTagsGenetator({
    required AppInfoServices appInfoServices,
  }) : _appInfoServices = appInfoServices;

  // TODO: Review entity.dart file
  @override
  Map<String, List<Tag>> generateTags(ARFSTagsArgs arguments) {
    final bundleDataItemTags = _bundleDataItemTags;
    final entityTags = _entityTags(arguments);
    final appTags = _appTags;

    final dataItemTags = [
      ...appTags,
      Tag(EntityTag.contentType, arguments.contentType),
    ];

    final entityMedataTags = [...entityTags, ...appTags];

    return {
      'data-item': dataItemTags,
      'bundle-data-item': bundleDataItemTags,
      'entity': entityMedataTags,
    };
  }

  List<Tag> _entityTags(
    ARFSTagsArgs arguments,
  ) {
    ARFSTagsValidator.validate(arguments);

    List<Tag> tags = [];

    final driveId = Tag(EntityTag.driveId, arguments.driveId!);

    tags.add(driveId);

    final appInfo = _appInfoServices.appInfo;

    String contentType;

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
          tags.add(Tag(EntityTag.driveAuthMode, 'private'));
        }

        tags.add(Tag(EntityTag.entityType, EntityType.drive.name));

        break;
    }

    return tags;
  }

  List<Tag> get _appTags {
    final appInfo = _appInfoServices.appInfo;

    final appVersion = Tag(EntityTag.appVersion, appInfo.version);
    final appPlatform = Tag(EntityTag.appPlatform, appInfo.platform);
    final unixTime = Tag(
      EntityTag.unixTime,
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    );
    final appName = Tag(EntityTag.appName, 'ArDrive-App');

    return [
      appName,
      appPlatform,
      appVersion,
      unixTime,
    ];
  }

  List<Tag> get _bundleDataItemTags {
    return [
      ..._appTags,
      Tag('Tip-Type', 'data upload'),
    ];
  }

  // TODO: Review this
  // List<Tag> get _uTags {
  //   return [
  //     Tag(EntityTag.appName, 'SmartWeaveAction'),
  //     Tag(EntityTag.appVersion, '0.3.0'),
  //     Tag(EntityTag.input, '{"function":"mint"}'),
  //     Tag(EntityTag.contract, 'KTzTXT_ANmF84fWEK HzWURD1LWd9QaFR9yfYUwH2Lxw'),
  //   ];
  // }
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

class ARFSTagsArgs {
  final String? driveId;
  final String? parentFolderId;
  final String? entityId;
  final bool? isPrivate;
  final String contentType;
  final EntityType entity;

  ARFSTagsArgs({
    this.driveId,
    this.parentFolderId,
    this.isPrivate,
    this.entityId,
    required this.entity,
    required this.contentType,
  });
}
