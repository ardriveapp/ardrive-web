import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

class IOCacheStorage {
  Future<String> saveEntityOnCacheDir(IOFile entity) async {
    final cacheDir = await _getCacheDir();

    debugPrint('saving file on local storage');

    final file = File('${cacheDir.path}/${entity.name}');

    final readStream = File(entity.path).openRead();

    final writeStream = await file.open(mode: FileMode.write);

    await for (List<int> chunk in readStream) {
      await writeStream.writeFrom(chunk);
    }

    await writeStream.close();

    return file.path;
  }

  Future<IOFile> getFileFromStorage(String fileName) async {
    debugPrint('getting file from storage');

    final adapter = IOFileAdapter();

    final cacheDir = await _getCacheDir();

    final file = File('${cacheDir.path}/$fileName');

    return adapter.fromFile(file);
  }

  Future<void> freeLocalStorage() async {
    debugPrint('getting file from storage');

    final cacheDir = await _getCacheDir();

    cacheDir.deleteSync(recursive: true);
  }

  Future<Directory> _getCacheDir() async {
    final dir = await path_provider.getApplicationDocumentsDirectory();

    final cacheDir = Directory('${dir.path}/cache');

    if (!cacheDir.existsSync()) {
      await cacheDir.create();
    }

    return cacheDir;
  }
}
