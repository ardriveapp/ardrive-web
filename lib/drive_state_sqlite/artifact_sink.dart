/// Where an artifact database is built, and where a received one is put so
/// SQLite can open it.
///
/// A real file on native and in a CLI; a virtual filesystem entry in a
/// browser. `ATTACH` needs a path, and the two platforms disagree about what a
/// path is, so this is the one seam the SQLite artifact needs that the JSON
/// one did not.
library;

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';

import 'artifact_sink_unsupported.dart'
    if (dart.library.html) 'artifact_sink_web.dart'
    if (dart.library.io) 'artifact_sink_io.dart' as impl;

/// Thrown when this platform cannot host an attached database.
///
/// Not an error to be fixed at the call site: the caller turns it into a
/// refusal with a reason, exactly as it would for any other precondition.
class ArtifactSinkUnsupported implements Exception {
  final String detail;
  ArtifactSinkUnsupported(this.detail);
  @override
  String toString() => 'ArtifactSinkUnsupported: $detail';
}

/// True when this platform can build and read artifacts at all. Checked before
/// anything is exported, so a user on an unsupported platform is told why
/// rather than shown a failure.
bool get artifactSinkSupported => impl.artifactSinkSupported;

/// A place to build an artifact, named for [label] so concurrent exports do
/// not collide.
Future<ArtifactSink> createArtifactSink(String label) =>
    impl.createArtifactSink(label);

/// A place to put received bytes so they can be attached.
Future<ArtifactSource> createArtifactSource(String label, List<int> bytes) =>
    impl.createArtifactSource(label, bytes);
