import 'dart:async';
import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as path;

/// Base class for agnostic platform folders.
///
/// `listContent` should return a list of `IOEntity` where it can be both
/// `IOFile` and `IOFolder`
abstract class IOFolder extends Equatable implements IOEntity {
  Future<List<IOEntity>> listContent();
}

/// Handle the dart:io API `FileSystemEntities` and mounts the folder hierachy
/// to the given folder.
///
/// `_mountFolderChildren` mounts recursiverly the folder hierarchy. It gets only
/// the current level entities loading only `IOFile` and `IOFolder`. To get the content
/// of a folder under this, you should call `listContent` and get the child's folder
/// content
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

    return IOFileAdapter().fromFile(fsEntity as File);
  }

  @override
  List<Object?> get props => [name, path];
}

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
