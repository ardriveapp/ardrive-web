/// The page's side of the database worker (`web/db_worker.dart`).
///
/// See docs/WEB_DATABASE.md. The worker holds SQLite and its OPFS files; this
/// starts it, opens the database in it, and hands drift a connection to it.
library;

import 'dart:async';
// Web-only: reached through the conditional import in database.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:ardrive/models/database/web_worker/port_channel.dart';
import 'package:drift/drift.dart';
import 'package:drift/remote.dart';

/// Why the worker did not open the database.
enum WorkerOpenFailure {
  /// Another tab's worker holds the OPFS files.
  busy,

  /// This browser has no OPFS.
  unsupported,

  /// A reader's copy failed `PRAGMA integrity_check`.
  corrupt,

  /// Anything else, including a worker script that never loaded.
  error,
}

class WorkerOpenResult {
  final WorkerOpenFailure? failure;

  /// Whether OPFS already held this user's database.
  final bool hadData;

  /// Whether the database still has to be filled from an older store.
  final bool needsMigration;
  final String? error;

  const WorkerOpenResult._(
    this.failure, {
    this.hadData = false,
    this.needsMigration = false,
    this.error,
  });

  bool get isOpen => failure == null;
}

/// How long the worker may take to answer one request before it is treated
/// as gone. Opening includes fetching and compiling sqlite3.wasm.
const _requestTimeout = Duration(seconds: 30);

class WebDatabaseWorker {
  final html.Worker _worker;
  var _terminated = false;

  /// Completes when the worker reports an error it did not answer: most often
  /// a script that never loaded. One listener for the worker's life.
  final _failed = Completer<Map<String, Object?>>();

  WebDatabaseWorker._(this._worker) {
    _worker.onError.listen((e) {
      if (_failed.isCompleted) return;
      _failed.complete({
        'ok': false,
        'reason': 'error',
        'error': 'the database worker failed: '
            '${e is html.ErrorEvent ? e.message : e.type}',
      });
    });
  }

  /// Starts the worker from [scriptUrl].
  ///
  /// A script that is missing or fails to load surfaces as
  /// [WorkerOpenFailure.error] on the first request, not here: a `Worker`
  /// reports a load failure only through its error event.
  static WebDatabaseWorker start(String scriptUrl) =>
      WebDatabaseWorker._(html.Worker(scriptUrl));

  Future<Map> _request(
    String kind, [
    Map<String, Object?> args = const {},
    List<Object> transfer = const [],
  ]) async {
    if (_terminated) {
      return {'ok': false, 'reason': 'error', 'error': 'worker terminated'};
    }
    final channel = html.MessageChannel();
    final answer = channel.port2.onMessage.first.then((e) => e.data as Map);
    _worker.postMessage(
      {'kind': kind, 'reply': channel.port1, ...args},
      [channel.port1, ...transfer],
    );
    try {
      return await Future.any([answer, _failed.future])
          .timeout(_requestTimeout);
    } on TimeoutException {
      return {'ok': false, 'reason': 'error', 'error': '$kind timed out'};
    } finally {
      channel.port2.close();
    }
  }

  static WorkerOpenResult _openResult(Map answer) {
    if (answer['ok'] == true) {
      return WorkerOpenResult._(
        null,
        hadData: answer['needsMigration'] != true,
        needsMigration: answer['needsMigration'] == true,
      );
    }
    final failure = switch (answer['reason']) {
      'busy' => WorkerOpenFailure.busy,
      'unsupported' => WorkerOpenFailure.unsupported,
      'corrupt' => WorkerOpenFailure.corrupt,
      _ => WorkerOpenFailure.error,
    };
    return WorkerOpenResult._(
      failure,
      hadData: answer['hadData'] == true,
      error: answer['error'] as String?,
    );
  }

  /// Opens the OPFS database for writing.
  Future<WorkerOpenResult> openWriter({
    required String name,
    required String sqlite3Url,
  }) async =>
      _openResult(await _request('open', {
        'name': name,
        'mode': 'writer',
        'sqlite3Url': sqlite3Url,
      }));

  /// Opens an in-memory copy, [seed], for a tab that does not write.
  Future<WorkerOpenResult> openReader({
    required String name,
    required String sqlite3Url,
    required Uint8List? seed,
  }) async =>
      _openResult(await _request('open', {
        'name': name,
        'mode': 'reader',
        'sqlite3Url': sqlite3Url,
        'seed': seed,
      }));

  /// Fills a new OPFS database from an older store's [bytes], or marks it as
  /// starting fresh when there are none. Returns whether [bytes] were taken;
  /// bytes that are not a sound SQLite database are refused, and the user
  /// starts fresh, as #2197's migration does.
  Future<({bool migrated, bool rejected})> migrate(Uint8List? bytes) async {
    final answer = await _request('migrate', {'bytes': bytes});
    if (answer['ok'] != true) {
      throw StateError('migration failed: ${answer['error']}');
    }
    return (
      migrated: answer['migrated'] == true,
      rejected: answer['rejected'] == true,
    );
  }

  /// Starts drift's server in the worker and returns the connection to it.
  /// Closing the connection terminates the worker, which releases the OPFS
  /// files for the next tab or the next open.
  Future<DatabaseConnection> serve() async {
    final channel = html.MessageChannel();
    final answer =
        await _request('serve', {'port': channel.port1}, [channel.port1]);
    if (answer['ok'] != true) {
      throw StateError('the database worker did not serve: ${answer['error']}');
    }
    final connection =
        await connectToRemoteAndInitialize(channel.port2.channel());
    return connection.interceptWith(_TerminateOnClose(this));
  }

  Future<void> putFile(String path, Uint8List bytes) async {
    final answer = await _request('putFile', {'path': path, 'bytes': bytes});
    if (answer['ok'] != true) throw StateError('putFile: ${answer['error']}');
  }

  /// The file's bytes, or null when it does not exist.
  Future<Uint8List?> readFile(String path) async {
    final answer = await _request('readFile', {'path': path});
    if (answer['ok'] == true) return answer['bytes'] as Uint8List;
    if (answer['reason'] == 'missing') return null;
    throw StateError('readFile: ${answer['error']}');
  }

  Future<void> deleteFile(String path) async {
    final answer = await _request('deleteFile', {'path': path});
    if (answer['ok'] != true) {
      throw StateError('deleteFile: ${answer['error']}');
    }
  }

  void terminate() {
    if (_terminated) return;
    _terminated = true;
    _worker.terminate();
  }
}

class _TerminateOnClose extends QueryInterceptor {
  final WebDatabaseWorker worker;
  _TerminateOnClose(this.worker);

  @override
  Future<void> close(QueryExecutor inner) async {
    try {
      await inner.close();
    } finally {
      worker.terminate();
    }
  }
}

/// The database file another tab's worker holds, read straight from OPFS, or
/// null when OPFS holds none. Possible while that tab writes: only a sync
/// access handle is exclusive, and this read takes none. A read that lands
/// during a commit can be torn; the reader's worker checks it.
Future<Uint8List?> readOpfsCopy(String name) async {
  final navigator = js_util.getProperty<Object?>(html.window, 'navigator');
  final storage = js_util.getProperty<Object?>(navigator!, 'storage');
  if (storage == null || !js_util.hasProperty(storage, 'getDirectory')) {
    return null;
  }
  try {
    Object directory = await js_util.promiseToFuture<Object>(
        js_util.callMethod(storage, 'getDirectory', []));
    for (final segment in ['ardrive-db', name]) {
      directory = await js_util.promiseToFuture<Object>(
          js_util.callMethod(directory, 'getDirectoryHandle', [segment]));
    }
    final handle = await js_util.promiseToFuture<Object>(
        js_util.callMethod(directory, 'getFileHandle', ['database']));
    final file = await js_util
        .promiseToFuture<Object>(js_util.callMethod(handle, 'getFile', []));
    final buffer = await js_util.promiseToFuture<ByteBuffer>(
        js_util.callMethod(file, 'arrayBuffer', []));
    final bytes = buffer.asUint8List();
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// Removes this database's OPFS directory, once [worker] has let go of it, or
/// returns false if it is still held after about five seconds.
///
/// The file is first copied beside it as `<name>-reset-<time>`, whole, as
/// it was: a reset is for a database that will not open, and the copy keeps
/// what it held (a saved wallet above all) for anyone who can still read it.
/// The copy is best effort: a browser that cannot write OPFS files from the
/// page (Safari) keeps none.
Future<bool> removeOpfsDatabase(String name,
    {WebDatabaseWorker? worker}) async {
  worker?.terminate();
  final navigator = js_util.getProperty<Object?>(html.window, 'navigator');
  final storage = js_util.getProperty<Object?>(navigator!, 'storage');
  if (storage == null || !js_util.hasProperty(storage, 'getDirectory')) {
    return true;
  }
  final Object parent;
  try {
    final root = await js_util.promiseToFuture<Object>(
        js_util.callMethod(storage, 'getDirectory', []));
    parent = await js_util.promiseToFuture<Object>(
        js_util.callMethod(root, 'getDirectoryHandle', ['ardrive-db']));
  } catch (_) {
    return true; // OPFS never held a database here.
  }

  final copy = await readOpfsCopy(name);
  if (copy != null) {
    try {
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final handle = await js_util
          .promiseToFuture<Object>(js_util.callMethod(parent, 'getFileHandle', [
        '$name-reset-$stamp',
        js_util.jsify({'create': true})
      ]));
      final writable = await js_util.promiseToFuture<Object>(
          js_util.callMethod(handle, 'createWritable', []));
      await js_util.promiseToFuture<Object?>(
          js_util.callMethod(writable, 'write', [copy]));
      await js_util
          .promiseToFuture<Object?>(js_util.callMethod(writable, 'close', []));
    } catch (_) {}
  }

  for (final wait in [Duration.zero, ..._releaseWaits]) {
    await Future<void>.delayed(wait);
    try {
      await js_util
          .promiseToFuture<Object?>(js_util.callMethod(parent, 'removeEntry', [
        name,
        js_util.jsify({'recursive': true})
      ]));
      return true;
    } catch (e) {
      if ('$e'.contains('NotFound')) return true;
    }
  }
  return false;
}

/// How long a tab holding the writer lock waits, between attempts, for files
/// a departed worker still holds. About five seconds in all.
const _releaseWaits = [
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 400),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1500),
  Duration(milliseconds: 2000),
];

/// Opens the database through the worker, or returns null for the caller to
/// use the IndexedDB path (docs/WEB_DATABASE.md §2, §3).
///
/// [isWriter] is whether this tab holds the writer lock. [readMigrationSource]
/// reads the store an OPFS database is first filled from; if it throws, the
/// worker is given up and null returned, so the IndexedDB path, which has its
/// own retries, takes this start.
Future<({DatabaseConnection connection, WebDatabaseWorker worker})?>
    openThroughWorker({
  required String scriptUrl,
  required String name,
  required String sqlite3Url,
  required bool isWriter,
  required Future<Uint8List?> Function() readMigrationSource,
  void Function(String message)? log,
}) async {
  // Whatever goes wrong here, the IndexedDB path still opens the database:
  // nothing in the worker is allowed to keep the app from starting.
  WebDatabaseWorker? started;
  try {
    started = WebDatabaseWorker.start(scriptUrl);
    return await _openThroughWorker(
      started,
      name: name,
      sqlite3Url: sqlite3Url,
      isWriter: isWriter,
      readMigrationSource: readMigrationSource,
      log: log,
    );
  } catch (e) {
    log?.call('the database worker failed: $e');
    started?.terminate();
    return null;
  }
}

Future<({DatabaseConnection connection, WebDatabaseWorker worker})?>
    _openThroughWorker(
  WebDatabaseWorker worker, {
  required String name,
  required String sqlite3Url,
  required bool isWriter,
  required Future<Uint8List?> Function() readMigrationSource,
  void Function(String message)? log,
}) async {
  var opfsHasData = false;

  if (isWriter) {
    var opened = await worker.openWriter(name: name, sqlite3Url: sqlite3Url);
    // This tab holds the writer lock, so no other live tab is writing. Busy
    // files here are a worker that just went away, a reload most often,
    // whose handles the browser releases a moment later. Measured: a worker
    // terminated 200 ms earlier still held them.
    for (final wait in _releaseWaits) {
      if (opened.failure != WorkerOpenFailure.busy) break;
      await Future<void>.delayed(wait);
      opened = await worker.openWriter(name: name, sqlite3Url: sqlite3Url);
    }
    if (opened.isOpen) {
      if (opened.needsMigration) {
        final Uint8List? bytes;
        try {
          bytes = await readMigrationSource();
        } catch (e) {
          log?.call('could not read the older store to migrate it: $e');
          worker.terminate();
          return null;
        }
        final result = await worker.migrate(bytes);
        log?.call(result.migrated
            ? 'migrated ${bytes!.length} bytes into OPFS'
            : result.rejected
                ? 'the older store is not a sound database; starting fresh'
                : 'no older store; starting fresh');
      }
      return (connection: await worker.serve(), worker: worker);
    }
    log?.call('the OPFS database did not open: ${opened.failure?.name} '
        '${opened.error ?? ''}');
    opfsHasData = opened.hadData;
    if (opened.failure != WorkerOpenFailure.busy && !opfsHasData) {
      // Nothing here was ever this user's database: the IndexedDB path.
      worker.terminate();
      return null;
    }
  }

  // A tab that does not write, or a writer whose OPFS database is held or
  // will not open: a copy of the OPFS database, in memory.
  for (var attempt = 1; attempt <= 3; attempt++) {
    final copy = await readOpfsCopy(name);
    if (copy == null) {
      if (opfsHasData) break;
      // OPFS holds nothing: whoever writes is on the IndexedDB path, and so
      // is this tab.
      worker.terminate();
      return null;
    }
    final opened =
        await worker.openReader(name: name, sqlite3Url: sqlite3Url, seed: copy);
    if (opened.isOpen) {
      return (connection: await worker.serve(), worker: worker);
    }
    log?.call('the copy of the OPFS database was not sound '
        '(attempt $attempt): ${opened.failure?.name}');
    if (opened.failure != WorkerOpenFailure.corrupt) break;
    await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
  }
  final empty =
      await worker.openReader(name: name, sqlite3Url: sqlite3Url, seed: null);
  if (!empty.isOpen) {
    worker.terminate();
    return null;
  }
  log?.call('opened an empty session database');
  return (connection: await worker.serve(), worker: worker);
}
