import 'package:ardrive/core/arfs/entities/arfs_entities.dart' as arfs;
import 'package:ardrive/core/upload/upload_metadata.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/app/app_info_services.dart';
import 'package:ardrive_io/ardrive_io.dart';
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
  List<Tag> generateTags(T arguments);
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

    final id = const Uuid().v4();

    if (entity is IOFile) {
      ARFSUploadMetadataArgsValidator.validate(arguments, arfs.EntityType.file);

      final file = entity;

      return ARFSFileUploadMetadata(
        isPrivate: arguments.isPrivate,
        size: await file.length,
        lastModifiedDate: file.lastModifiedDate,
        dataContentType: file.contentType,
        driveId: arguments.driveId!,
        parentFolderId: arguments.parentFolderId!,
        tags: _tagsGenerator.generateTags(
          ARFSTagsArgs(
            driveId: arguments.driveId!,
            parentFolderId: arguments.parentFolderId!,
            entityId: id,
          ),
        ),
        name: file.name,
        id: id,
      );
    } else if (entity is IOFolder) {
      ARFSUploadMetadataArgsValidator.validate(
          arguments, arfs.EntityType.folder);

      final folder = entity;

      return ARFSFolderUploadMetatadata(
        isPrivate: arguments.isPrivate,
        driveId: arguments.driveId!,
        parentFolderId: arguments.parentFolderId,
        tags: _tagsGenerator.generateTags(
          ARFSTagsArgs(
            driveId: arguments.driveId!,
            parentFolderId: arguments.parentFolderId,
            entityId: id,
          ),
        ),
        name: folder.name,
        id: id,
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

    return ARFSDriveUploadMetadata(
      isPrivate: isPrivate,
      name: name,
      tags: _tagsGenerator.generateTags(
        ARFSTagsArgs(
          isPrivate: isPrivate,
          entityId: id,
        ),
      ),
      id: id,
    );
  }
}

class ARFSUploadMetadataArgs {
  final String? driveId;
  final String? parentFolderId;
  final String? privacy;
  final bool isPrivate;

  ARFSUploadMetadataArgs({
    required this.isPrivate,
    this.driveId,
    this.parentFolderId,
    this.privacy,
  });
}

class ARFSTagsGenetator implements TagsGenerator<ARFSTagsArgs> {
  final arfs.EntityType _entity;
  final AppInfoServices _appInfoServices;

  // constructor
  ARFSTagsGenetator({
    required arfs.EntityType entity,
    required AppInfoServices appInfoServices,
  })  : _entity = entity,
        _appInfoServices = appInfoServices;

  // TODO: Review entity.dart file
  @override
  List<Tag> generateTags(ARFSTagsArgs arguments) {
    return _appTags + _entityTags(_entity, arguments) + _uTags;
  }

  List<Tag> _entityTags(
    arfs.EntityType entity,
    ARFSTagsArgs arguments,
  ) {
    ARFSTagsValidator.validate(arguments, entity);

    List<Tag> tags = [];

    final driveId = Tag(EntityTag.driveId, arguments.driveId!);

    tags.add(driveId);

    switch (_entity) {
      case arfs.EntityType.file:
        tags.add(Tag(EntityTag.fileId, arguments.entityId!));
        tags.add(Tag(EntityTag.entityType, arfs.EntityType.file.name));
        tags.add(Tag(EntityTag.parentFolderId, arguments.parentFolderId!));

        break;
      case arfs.EntityType.folder:
        tags.add(Tag(EntityTag.folderId, arguments.entityId!));
        tags.add(Tag(EntityTag.entityType, arfs.EntityType.folder.name));

        if (arguments.parentFolderId != null) {
          tags.add(Tag(EntityTag.parentFolderId, arguments.parentFolderId!));
        }

        break;
      case arfs.EntityType.drive:
        if (arguments.isPrivate ?? false) {
          tags.add(Tag(EntityTag.driveAuthMode, 'private'));
        }

        tags.add(Tag(EntityTag.entityType, arfs.EntityType.drive.name));

        break;
    }

    return tags;
  }

  List<Tag> get _appTags {
    final appInfo = _appInfoServices.appInfo;

    final appVersion = Tag(EntityTag.appVersion, appInfo.version);
    final appPlatform = Tag(EntityTag.appPlatform, appInfo.platform);
    final arfsTag = Tag(EntityTag.arFs, appInfo.arfsVersion);
    final unixTime = Tag(
      EntityTag.unixTime,
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    );

    return [
      appVersion,
      appPlatform,
      arfsTag,
      unixTime,
    ];
  }

  List<Tag> get _uTags {
    return [
      Tag(EntityTag.appName, 'SmartWeaveAction'),
      Tag(EntityTag.appVersion, '0.3.0'),
      Tag(EntityTag.input, '{"function":"mint"}'),
      Tag(EntityTag.contract, 'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw'),
    ];
  }
}

class ARFSUploadMetadataArgsValidator {
  static void validate(ARFSUploadMetadataArgs args, arfs.EntityType entity) {
    switch (entity) {
      case arfs.EntityType.file:
        if (args.driveId == null) {
          throw ArgumentError('driveId must not be null');
        }
        if (args.parentFolderId == null) {
          throw ArgumentError('parentFolderId must not be null');
        }
        break;

      case arfs.EntityType.folder:
        if (args.driveId == null) {
          throw ArgumentError('driveId must not be null');
        }
        break;

      case arfs.EntityType.drive:
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
  static void validate(ARFSTagsArgs args, arfs.EntityType entity) {
    if (args.driveId == null) {
      throw ArgumentError('driveId must not be null');
    }

    switch (entity) {
      case arfs.EntityType.file:
        if (args.entityId == null) {
          throw ArgumentError('entityId must not be null');
        }
        if (args.parentFolderId == null) {
          throw ArgumentError('parentFolderId must not be null');
        }

        break;
      case arfs.EntityType.folder:
        if (args.entityId == null) {
          throw ArgumentError('entityId must not be null');
        }

        break;
      case arfs.EntityType.drive:
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

  ARFSTagsArgs({
    this.driveId,
    this.parentFolderId,
    this.isPrivate,
    this.entityId,
  });
}
