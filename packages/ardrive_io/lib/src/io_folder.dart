import 'dart:async';
import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';

/// Base class for agnostic platform folders.
///
/// `listContent` returns the folder structure in a tree of `IOEntity`.
///
/// `listSubfolders()` gets all folders from this folder tree
///
/// `listFiles()` gets all files from this folder tree
abstract class IOFolder extends Equatable implements IOEntity {
  Future<List<IOEntity>> listContent();
  Future<List<IOFolder>> listSubfolders();
  Future<List<IOFile>> listFiles();
}

/// Handle the dart:io API `FileSystemEntities` and mounts the folder hierachy
/// to the given folder.
class _FileSystemFolder extends IOFolder {
  _FileSystemFolder._({
    required this.name,
    required this.lastModifiedDate,
    required this.path,
    required List<FileSystemEntity> folderContent,
  }) : _folderContent = folderContent;

  final List<FileSystemEntity> _folderContent;

  @override
  final String name;

  @override
  final DateTime lastModifiedDate;

  @override
  final String path;

  Future<void> initFolder() async {
    await _mountFolderStructure();
  }

  @override
  Future<List<IOEntity>> listContent() async {
    return _mountFolderStructure();
  }

  @override
  Future<List<IOFile>> listFiles() async {
    if (Platform.isIOS) {
      await SecurityScopedResource.instance
          .startAccessingSecurityScopedResource(Directory(path));
    }
    final files = await secureScopedAction(
      (secureDir) => _getAllEntitiesFromType<IOFile>(this),
      Directory(path),
    );

    return files;
  }

  @override
  Future<List<IOFolder>> listSubfolders() async {
    return _getAllEntitiesFromType<IOFolder>(this);
  }

  /// `_mountFolderChildren` mounts recursiverly the folder hierarchy. It gets only
  /// the current level entities loading only `IOFile` and `IOFolder`
  Future<List<IOEntity>> _mountFolderStructure() async {
    List<IOEntity> children = [];

    for (var fs in _folderContent) {
      children.add(await _addFolderNode(fs));
    }

    return children;
  }

  Future<IOEntity> _addFolderNode(FileSystemEntity fsEntity) async {
    if (fsEntity is Directory) {
      final newNode = await IOFolderAdapter().fromFileSystemDirectory(fsEntity);

      for (var fs in fsEntity.listSync()) {
        final children = await newNode.listContent();
        children.add(await _addFolderNode(fs));
      }

      return newNode;
    }
    final ioFile = await IOFileAdapter().fromFile(fsEntity as File);

    return ioFile;
  }

  /// recursively get all entities from this folder filtering by the `IOEntity` `T` type
  Future<List<T>> _getAllEntitiesFromType<T extends IOEntity>(
      IOFolder ioFolder) async {
    final content = await ioFolder.listContent();
    final subFolders = content.whereType<IOFolder>();
    final entities = <T>[];

    for (IOFolder iof in subFolders) {
      entities.addAll(await _getAllEntitiesFromType(iof));
    }

    entities.addAll(content.whereType<T>());

    return entities;
  }

  @override
  List<Object?> get props => [name, path];
}

class _WebFolder extends IOFolder {
  _WebFolder(
    List<IOFile> files,
  ) : _files = files;
  @override
  final DateTime lastModifiedDate = DateTime.now();

  final List<IOFile> _files;

  @override
  Future<List<IOEntity>> listContent() {
    return Future.value(_files);
  }

  @override
  Future<List<IOFile>> listFiles() {
    return Future.value(_files);
  }

  @override
  Future<List<IOFolder>> listSubfolders() {
    throw UnimplementedError('IOFolder doesnt support list subfolders on Web');
  }

  @override
  final String name = '';

  @override
  final String path = '';

  @override
  List<Object?> get props => [name, path];
}

/// Adapts the `IOFolder` from different I/O sources
class IOFolderAdapter {
  /// Initialize loading the folder hierachy and return an `_FileSystemFolder` instance
  Future<IOFolder> fromFileSystemDirectory(Directory directory) async {
    if (Platform.isIOS) {
      await SecurityScopedResource.instance
          .startAccessingSecurityScopedResource(directory);
    }

    final content = directory.listSync();

    final selectedDirectoryPath = directory.path;

    final folder = _FileSystemFolder._(
      name: getBasenameFromPath(selectedDirectoryPath),
      lastModifiedDate: (await directory.stat()).modified,
      path: selectedDirectoryPath,
      folderContent: content,
    );

    await folder.initFolder();

    return folder;
  }

  IOFolder fromIOFiles(List<IOFile> files) {
    return _WebFolder(
      files,
    );
  }
}
