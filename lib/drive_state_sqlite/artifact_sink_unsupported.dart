/// Neither `dart:io` nor `dart:html`. Nothing here can host a database file.
library;

import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';

bool get artifactSinkSupported => false;

Future<ArtifactSink> createArtifactSink(String label) =>
    throw ArtifactSinkUnsupported('platform has no filesystem');

Future<ArtifactSource> createArtifactSource(String label, List<int> bytes) =>
    throw ArtifactSinkUnsupported('platform has no filesystem');
