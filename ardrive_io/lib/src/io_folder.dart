import 'dart:async';
import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as path;

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

  Future<void> initFolder() async {
    await _mountFolderChildren();
  }

  @override
  final String name;

  @override
  final DateTime lastModifiedDate;

  @override
  final String path;

  @override
  Future<List<IOEntity>> listContent() async {
    return _mountFolderChildren();
  }

  final List<FileSystemEntity> _folderContent;

  /// `_mountFolderChildren` mounts recursiverly the folder hierarchy. It gets only
  /// the current level entities loading only `IOFile` and `IOFolder`
  Future<List<IOEntity>> _mountFolderChildren() async {
    List<IOEntity> _children = [];

    for (var fs in _folderContent) {
      _children.add(await _addFolderNode(fs));
    }

    return _children;
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

  @override
  Future<List<IOFile>> listFiles() async {
    return _getAllEntitiesFromType<IOFile>(this);
  }

  @override
  Future<List<IOFolder>> listSubfolders() async {
    return _getAllEntitiesFromType<IOFolder>(this);
  }

  /// recursively get all entities from this folder filtering by the `IOEntity` `T` type
  Future<List<T>> _getAllEntitiesFromType<T extends IOEntity>(
      IOFolder ioFolder) async {
    final content = await ioFolder.listContent();
    final subFolders = content.whereType<IOFolder>();
    final entities = <T>[];

    if (subFolders.isNotEmpty) {
      for (IOFolder iof in subFolders) {
        entities.addAll(await _getAllEntitiesFromType(iof));
      }
    }

    entities.addAll(content.whereType<T>());

    return entities;
  }

  @override
  List<Object?> get props => [name, path];
}

/// Adapts the `IOFolder` from different I/O sources
class IOFolderAdapter {
  /// Initialize loading the folder hierachy and return an `_FileSystemFolder` instance
  Future<IOFolder> fromFileSystemDirectory(Directory directory) async {
    final content = directory.listSync();
    final selectedDirectoryPath = directory.path;

    final folder = _FileSystemFolder._(
        name: path.basename(selectedDirectoryPath),
        lastModifiedDate: (await directory.stat()).modified,
        path: selectedDirectoryPath,
        folderContent: content);

    await folder.initFolder();

    return folder;
  }
}
