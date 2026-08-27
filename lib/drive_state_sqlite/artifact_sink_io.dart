/// Native and CLI: an ordinary file in a temporary directory.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';

bool get artifactSinkSupported => true;

Future<ArtifactSink> createArtifactSink(String label) async {
  final dir = await Directory.systemTemp.createTemp('drive_state_$label');
  return _FileSink('${dir.path}/artifact.db', dir);
}

Future<ArtifactSource> createArtifactSource(
  String label,
  List<int> bytes,
) async {
  final dir = await Directory.systemTemp.createTemp('drive_state_$label');
  final path = '${dir.path}/received.db';
  await File(path).writeAsBytes(bytes, flush: true);
  return _FileSource(path, dir);
}

class _FileSink implements ArtifactSink {
  @override
  final String path;
  final Directory _dir;
  _FileSink(this.path, this._dir);

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  Future<void> dispose() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }
}

class _FileSource implements ArtifactSource {
  @override
  final String path;
  final Directory _dir;
  _FileSource(this.path, this._dir);

  @override
  Future<void> dispose() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }
}
