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

  group('a retry over an attempt that has not stopped', () {
    late MockUploadDispatcher dispatcher;
    late UploadController controller;
    late List<String> posted;
    late Completer<void> gate;
    late int attempt;
    late bool Function() staleVerifyCancel;
    late UploadController staleController;
    late Completer<void> retrySending;
    late List<List<UploadTask>> done;

    /// A refuses with a 402. B is either still preparing ([bPreparing]) or
    /// already posting with nothing left to cancel it, behind [gate].
    void setUpAttempts({required bool bPosting}) {
      dispatcher = MockUploadDispatcher();
      controller = UploadController(
        StreamController<UploadProgress>(),
        dispatcher,
        numOfWorkers: 2,
        maxTasksPerWorker: 1,
        stopTimeout: const Duration(milliseconds: 200),
      );
      done = [];
      controller.onError((_) {});
      controller.onDone(done.add);
      controller.onProgressChange((_) {});
      controller.addTask(makeTask('A'));
      controller.addTask(makeTask('B'));
      posted = [];
      gate = Completer<void>();
      retrySending = Completer<void>()..complete();
      attempt = 1;

      when(() => dispatcher.send(
            task: any(named: 'task'),
            wallet: any(named: 'wallet'),
            controller: any(named: 'controller'),
            verifyCancel: any(named: 'verifyCancel'),
          )).thenAnswer((inv) async {
        final t = inv.namedArguments[#task] as UploadTask;
        final c = inv.namedArguments[#controller] as UploadController;
        final verifyCancel =
            inv.namedArguments[#verifyCancel] as bool Function();
        final myAttempt = attempt;
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
          staleVerifyCancel = verifyCancel;
          staleController = c;
          if (bPosting) {
            await gate.future;
            posted.add('B@1');
            c.updateProgress(
                task: c.tasks[t.id]!
                    .copyWith(status: UploadStatus.complete, progress: 1));
            return UploadResult(success: true);
          }
          await gate.future;
        }
        if (myAttempt == 2 && t.id == 'B') await retrySending.future;
        if (verifyCancel()) {
          return UploadResult(success: false, error: Exception('canceled'));
        }
        posted.add('${t.id}@$myAttempt');
        c.updateProgress(
            task: c.tasks[t.id]!
                .copyWith(status: UploadStatus.complete, progress: 1));
        return UploadResult(success: true);
      });
    }

    test(
        'is refused while a post of it is still on its way, and works once '
        'it has finished, sending nothing twice', () async {
      setUpAttempts(bPosting: true);
      controller.sendTasks(MockWallet());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      attempt = 2;
      await expectLater(controller.retryFailedTasks(MockWallet()),
          throwsA(isA<PreviousAttemptStillRunning>()));
      expect(posted, isEmpty, reason: 'nothing sent over the old attempt');

      // The old post lands.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(posted, ['B@1']);

      await controller.retryFailedTasks(MockWallet());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(posted, ['B@1', 'A@2'], reason: 'B is not sent again');
    });

    test(
        'a task still preparing past the timeout is not sent, by either '
        'attempt, until the retry sends it', () async {
      setUpAttempts(bPosting: false);
      controller.sendTasks(MockWallet());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      attempt = 2;
      await expectLater(controller.retryFailedTasks(MockWallet()),
          throwsA(isA<PreviousAttemptStillRunning>()));

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(posted, isEmpty, reason: 'the refused attempt stays canceled');

      retrySending = Completer<void>();
      await controller.retryFailedTasks(MockWallet());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(posted, ['A@2']);

      // While the retry is still sending B, whatever the old attempt kept
      // hold of no longer works: it is told it is canceled, and what it
      // reports goes nowhere, so it can't finish the retry's B for it.
      expect(staleVerifyCancel(), isTrue);
      staleController.updateProgress(
          task: controller.tasks['B']!
              .copyWith(status: UploadStatus.complete, progress: 1));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(controller.tasks['B']!.status, isNot(UploadStatus.complete));
      expect(done, isEmpty);

      retrySending.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(posted, ['A@2', 'B@2']);
      expect(done, hasLength(1));
    });
  });
}
