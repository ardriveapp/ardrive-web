import 'package:ardrive/core/arfs/entities/arfs_entities.dart' as arfs;
import 'package:ardrive/core/upload/upload_metadata.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/app/app_info_services.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:uuid/uuid.dart';

/// this class will get an `IOFile` and mounts the metadata for it
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
    required String privacy,
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
        size: await file.length,
        lastModifiedDate: file.lastModifiedDate,
        dataContentType: file.contentType,
        driveId: arguments.driveId!,
        parentFolderId: arguments.parentFolderId!,
        tags: _tagsGenerator.generateTags(arguments),
        name: file.name,
        id: id,
      );
    } else if (entity is IOFolder) {
      ARFSUploadMetadataArgsValidator.validate(
          arguments, arfs.EntityType.folder);

      final folder = entity;

      return ARFSFolderUploadMetatadata(
        driveId: arguments.driveId!,
        parentFolderId: arguments.parentFolderId,
        tags: _tagsGenerator.generateTags(arguments),
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
    required String privacy,
  }) async {
    final id = const Uuid().v4();

    return ARFSDriveUploadMetadata(
      name: name,
      tags: _tagsGenerator.generateTags(
        ARFSUploadMetadataArgs(privacy: privacy),
      ),
      id: id,
    );
  }
}

class ARFSUploadMetadataArgs {
  final String? driveId;
  final String? fileId;
  final String? folderId;
  final String? parentFolderId;
  final String? privacy;

  ARFSUploadMetadataArgs({
    this.driveId,
    this.fileId,
    this.folderId,
    this.parentFolderId,
    this.privacy,
  });
}

class ARFSTagsGenetator implements TagsGenerator<ARFSUploadMetadataArgs> {
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
  List<Tag> generateTags(ARFSUploadMetadataArgs arguments) {
    ARFSUploadMetadataArgsValidator.validate(arguments, _entity);

    return _appTags + _entityTags(_entity, arguments) + _uTags;
  }

  List<Tag> _entityTags(
      arfs.EntityType entity, ARFSUploadMetadataArgs arguments) {
    List<Tag> tags = [];

    final driveId = Tag(EntityTag.driveId, arguments.driveId!);

    tags.add(driveId);

    switch (_entity) {
      case arfs.EntityType.file:
        tags.add(Tag(EntityTag.fileId, arguments.fileId!));

        if (arguments.parentFolderId != null) {
          tags.add(Tag(EntityTag.parentFolderId, arguments.parentFolderId!));
        }

        break;
      case arfs.EntityType.folder:
        tags.add(Tag(EntityTag.folderId, arguments.folderId!));

        if (arguments.parentFolderId != null) {
          tags.add(Tag(EntityTag.parentFolderId, arguments.parentFolderId!));
        }

        break;
      case arfs.EntityType.drive:
        if (arguments.privacy == DrivePrivacy.private) {
          tags.add(Tag(EntityTag.driveAuthMode, arguments.privacy!));
        }

        break;
    }

    return tags;
  }

  List<Tag> get _appTags {
    final appInfo = _appInfoServices.appInfo;

    final appVersion = Tag(EntityTag.appVersion, appInfo.version);
    final appPlatform = Tag(EntityTag.appPlatform, appInfo.platform);
    final arfsTag = Tag(EntityTag.arFs, appInfo.arfsVersion);
    final entityTag = Tag(EntityTag.entityType, _entity.name);
    final unixTime = Tag(
      EntityTag.unixTime,
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    );

    return [
      appVersion,
      appPlatform,
      arfsTag,
      entityTag,
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
        if (args.fileId == null) {
          throw ArgumentError('fileId must not be null');
        }
        if (args.parentFolderId == null) {
          throw ArgumentError('parentFolderId must not be null');
        }
        break;

      case arfs.EntityType.folder:
        if (args.driveId == null) {
          throw ArgumentError('driveId must not be null');
        }
        if (args.folderId == null) {
          throw ArgumentError('folderId must not be null');
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
