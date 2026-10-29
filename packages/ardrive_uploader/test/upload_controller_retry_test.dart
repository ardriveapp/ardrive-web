import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/upload_dispatcher.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockUploadDispatcher extends Mock implements UploadDispatcher {}

class MockIOFile extends Mock implements IOFile {}

class MockARFSFileUploadMetadata extends Mock
    implements ARFSFileUploadMetadata {}

class MockWallet extends Mock implements Wallet {}

class FakeUploadTask extends Fake implements UploadTask {}

class FakeUploadController extends Fake implements UploadController {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUploadTask());
    registerFallbackValue(MockWallet());
    registerFallbackValue(FakeUploadController());
  });

  test(
      'a retry after Turbo refused payment is done when its tasks are, not '
      'as soon as it starts', () async {
    final dispatcher = MockUploadDispatcher();
    final controller = UploadController(
      StreamController<UploadProgress>(),
      dispatcher,
      numOfWorkers: 1,
      maxTasksPerWorker: 1,
    );
    final metadata = MockARFSFileUploadMetadata();
    when(() => metadata.size).thenReturn(10);
    final task = FileUploadTask(
      file: MockIOFile(),
      metadata: metadata,
      content: [metadata],
      type: UploadType.turbo,
      uploadThumbnail: false,
    );
    final errors = <List<UploadTask>>[];
    final done = <List<UploadTask>>[];
    controller.onError(errors.add);
    controller.onDone(done.add);
    controller.onProgressChange((_) {});
    controller.addTask(task);

    // The first attempt: Turbo answers 402.
    when(() => dispatcher.send(
          task: any(named: 'task'),
          wallet: any(named: 'wallet'),
          controller: any(named: 'controller'),
          verifyCancel: any(named: 'verifyCancel'),
        )).thenAnswer((inv) async {
      final t = inv.namedArguments[#task] as UploadTask;
      controller.updateProgress(
          task: t.copyWith(status: UploadStatus.preparationDone));
      controller.updateProgress(
          task: t.copyWith(status: UploadStatus.inProgress));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return UploadResult(
          success: false,
          error: MetadataTransactionUploadException(
            message: 'refused',
            error: UnderFundException(message: '402'),
          ),
        );
    });
    controller.sendTasks(MockWallet());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(errors, isNotEmpty);
    expect(done, isEmpty);

    // The retry: still sending.
    final sending = Completer<UploadResult>();
    when(() => dispatcher.send(
          task: any(named: 'task'),
          wallet: any(named: 'wallet'),
          controller: any(named: 'controller'),
          verifyCancel: any(named: 'verifyCancel'),
        )).thenAnswer((inv) {
      final t = inv.namedArguments[#task] as UploadTask;
      controller.updateProgress(
          task: t.copyWith(status: UploadStatus.preparationDone));
      controller.updateProgress(
          task: t.copyWith(status: UploadStatus.inProgress));
      return sending.future;
    });
    await controller.retryFailedTasks(MockWallet());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(done, isEmpty, reason: 'nothing has been sent yet');

    // Sent.
    controller.updateProgress(
        task: controller.tasks.values.single
            .copyWith(status: UploadStatus.complete, progress: 1));
    sending.complete(UploadResult(success: true));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(done, hasLength(1));
  });
}
