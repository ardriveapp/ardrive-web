import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/upload_dispatcher.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockUploadDispatcher extends Mock implements UploadDispatcher {}

class MockIOFile extends Mock implements IOFile {}

class MockMeta extends Mock implements ARFSFileUploadMetadata {}

class MockWallet extends Mock implements Wallet {}

class FakeUploadTask extends Fake implements UploadTask {}

class FakeUploadController extends Fake implements UploadController {}

FileUploadTask makeTask(String id) {
  final m = MockMeta();
  when(() => m.size).thenReturn(10);
  return FileUploadTask(
    id: id,
    file: MockIOFile(),
    metadata: m,
    content: [m],
    type: UploadType.turbo,
    uploadThumbnail: false,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUploadTask());
    registerFallbackValue(MockWallet());
    registerFallbackValue(FakeUploadController());
  });

  test(
      'an attempt still preparing when Turbo refuses another is not sent '
      'again alongside the retry', () async {
    final dispatcher = MockUploadDispatcher();
    final controller = UploadController(
      StreamController<UploadProgress>(),
      dispatcher,
      numOfWorkers: 2,
      maxTasksPerWorker: 1,
    );
    controller.onError((_) {});
    controller.onDone((_) {});
    controller.onProgressChange((_) {});
    controller.addTask(makeTask('A'));
    controller.addTask(makeTask('B'));

    // Every POST that actually goes out (the strategy checks verifyCancel
    // after preparing, then sends), by task id.
    final posted = <String>[];
    final bPreparing = Completer<void>();
    var attempt = 1;

    when(() => dispatcher.send(
          task: any(named: 'task'),
          wallet: any(named: 'wallet'),
          controller: any(named: 'controller'),
          verifyCancel: any(named: 'verifyCancel'),
        )).thenAnswer((inv) async {
      final t = inv.namedArguments[#task] as UploadTask;
      final verifyCancel = inv.namedArguments[#verifyCancel] as bool Function();
      final myAttempt = attempt;
      controller.updateProgress(
          task: t.copyWith(status: UploadStatus.creatingBundle));
      if (myAttempt == 1 && t.id == 'A') {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return UploadResult(
          success: false,
          error: MetadataTransactionUploadException(
            message: 'refused',
            error: UnderFundException(message: '402'),
          ),
        );
      }
      if (myAttempt == 1 && t.id == 'B') {
        // A large file still bundling and signing.
        await bPreparing.future;
      }
      if (verifyCancel()) {
        return UploadResult(success: false, error: Exception('canceled'));
      }
      posted.add('${t.id}@$myAttempt');
      controller.updateProgress(
          task: controller.tasks[t.id]!
              .copyWith(status: UploadStatus.complete, progress: 1));
      return UploadResult(success: true);
    });

    controller.sendTasks(MockWallet());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The review again; the person has the credits and presses Upload.
    attempt = 2;
    final retry = controller.retryFailedTasks(MockWallet());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The retry waits for the first attempt to stop, and nothing is sent
    // again while it is still preparing B.
    expect(posted, isEmpty);

    // The first attempt's B finishes preparing.
    bPreparing.complete();
    await retry;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(posted.where((p) => p.startsWith('B')), hasLength(1),
        reason: 'B must be posted once, not by both attempts');
    expect(posted, containsAll(['A@2', 'B@2']),
        reason: 'the retry sends both, once the first attempt has stopped');
  });

  test('a second press on retry sends nothing twice', () async {
    final dispatcher = MockUploadDispatcher();
    final controller = UploadController(
      StreamController<UploadProgress>(),
      dispatcher,
      numOfWorkers: 1,
      maxTasksPerWorker: 1,
    );
    controller.onError((_) {});
    controller.onDone((_) {});
    controller.onProgressChange((_) {});
    controller.addTask(makeTask('A'));

    final sent = <String>[];
    var refuse = true;
    when(() => dispatcher.send(
          task: any(named: 'task'),
          wallet: any(named: 'wallet'),
          controller: any(named: 'controller'),
          verifyCancel: any(named: 'verifyCancel'),
        )).thenAnswer((inv) async {
      final t = inv.namedArguments[#task] as UploadTask;
      if (refuse) {
        return UploadResult(
          success: false,
          error: MetadataTransactionUploadException(
            message: 'refused',
            error: UnderFundException(message: '402'),
          ),
        );
      }
      sent.add(t.id);
      controller.updateProgress(
          task: controller.tasks[t.id]!
              .copyWith(status: UploadStatus.complete, progress: 1));
      return UploadResult(success: true);
    });

    controller.sendTasks(MockWallet());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    refuse = false;
    await Future.wait([
      controller.retryFailedTasks(MockWallet()),
      controller.retryFailedTasks(MockWallet()),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(sent, ['A']);
  });

  test('a canceled upload is never reported done', () async {
    final dispatcher = MockUploadDispatcher();
    final controller = UploadController(
      StreamController<UploadProgress>(),
      dispatcher,
      numOfWorkers: 1,
      maxTasksPerWorker: 1,
    );
    controller.addTask(makeTask('A'));
    final events = <String>[];
    controller.onDone((_) => events.add('done'));
    controller.onCancel((_) => events.add('cancel'));
    controller.onError((_) => events.add('error'));
    controller.onProgressChange((_) {});
    final never = Completer<UploadResult>();
    when(() => dispatcher.send(
          task: any(named: 'task'),
          wallet: any(named: 'wallet'),
          controller: any(named: 'controller'),
          verifyCancel: any(named: 'verifyCancel'),
        )).thenAnswer((inv) {
      final t = inv.namedArguments[#task] as UploadTask;
      controller.updateProgress(
          task: t.copyWith(status: UploadStatus.inProgress));
      return never.future;
    });
    controller.sendTasks(MockWallet());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await controller.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(events, ['cancel']);
  });
}
