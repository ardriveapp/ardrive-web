@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'prototype_suite.dart';

/// The VM half of the prototype. It proves the SQL in `artifact_pipeline.dart`
/// is correct; it says nothing about whether the browser can run it, which is
/// what `attach_web_test.dart` is for.
void main() {
  late Directory dir;

  runAttachPrototypeSuite(
    platform: 'vm/ffi',
    open: (path) => sqlite3.open(path),
    readBytes: (path) => File(path).readAsBytesSync(),
    writeBytes: (path, bytes) => File(path).writeAsBytesSync(bytes),
    pathFor: (name) => '${dir.path}/$name',
    reset: () {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir = Directory.systemTemp.createTempSync('d12_prototype');
    },
  );

  setUpAll(() => dir = Directory.systemTemp.createTempSync('d12_prototype'));
  tearDownAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('reports the library version this run proved things against', () {
    printOnFailure('sqlite ${sqlite3.version.libVersion}');
    expect(sqlite3.version.libVersion, isNotEmpty);
  });
}
