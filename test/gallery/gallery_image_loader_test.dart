import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCall {
  FakeCall(this.target, this.cancelWhen);
  final GalleryFetchTarget target;
  final Future<void> cancelWhen;
  final Completer<Uint8List> completer = Completer();
  bool aborted = false;
}

class FakeFetcher implements GalleryImageFetcher {
  final List<FakeCall> calls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  List<String> get started => calls.map((c) => c.target.fileId).toList();
  FakeCall call(String fileId) =>
      calls.lastWhere((c) => c.target.fileId == fileId);

  @override
  Future<Uint8List> fetch(
    GalleryFetchTarget target, {
    required Future<void> cancelWhen,
  }) {
    final c = FakeCall(target, cancelWhen);
    calls.add(c);
    cancelWhen.then((_) => c.aborted = true);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    return c.completer.future.whenComplete(() => inFlight--);
  }

  void succeed(String fileId, [int bytes = 100]) =>
      call(fileId).completer.complete(Uint8List(bytes));
  void fail(String fileId, Object e) => call(fileId).completer.completeError(e);
}

GalleryImageRequest req(
  String id, {
  bool isPrivate = false,
  int size = 5000,
  List<GalleryVariant>? variants,
}) =>
    GalleryImageRequest(
      fileId: id,
      isPrivate: isPrivate,
      variants: variants ??
          [GalleryVariant(txId: 'tx-$id', size: size, width: 512, height: 512)],
      tileWidth: 100,
      tileHeight: 100,
      devicePixelRatio: 1,
    );

void main() {
  const config = GalleryLoaderConfig(
    maxConcurrent: 2,
    idleDelay: Duration(milliseconds: 150),
    retryDelay: Duration(milliseconds: 100),
    cacheBytes: 1000,
  );

  late FakeFetcher fetcher;
  late GalleryImageLoader loader;

  void run(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      fetcher = FakeFetcher();
      loader = GalleryImageLoader(fetcher: fetcher, config: config);
      body(async);
      loader.dispose();
    });
  }

  GalleryImageHandle show(String id, {double priority = 0, bool priv = false}) {
    final h = loader.acquire(req(id, isPrivate: priv));
    h.updatePosition(onScreen: true, priority: priority);
    return h;
  }

  test('never more than the cap in flight', () {
    run((async) {
      for (var i = 0; i < 6; i++) {
        show('f$i', priority: i.toDouble());
      }
      async.flushMicrotasks();
      expect(fetcher.inFlight, 2);
      for (var i = 0; i < 6; i++) {
        async.flushMicrotasks();
        final next = fetcher.calls.firstWhere((c) => !c.completer.isCompleted);
        next.completer.complete(Uint8List(10));
        async.flushMicrotasks();
      }
      expect(fetcher.calls.length, 6);
      expect(fetcher.maxInFlight, 2);
    });
  });

  test('off-screen items never start', () {
    run((async) {
      final h = loader.acquire(req('a'));
      h.updatePosition(onScreen: false);
      async.elapse(const Duration(seconds: 5));
      expect(fetcher.calls, isEmpty);
      expect(h.value.status, GalleryImageStatus.loading);
    });
  });

  test('leaving the screen cancels a queued item', () {
    run((async) {
      show('a', priority: 0);
      show('b', priority: 1);
      final c = show('c', priority: 2);
      async.flushMicrotasks();
      expect(fetcher.started, ['a', 'b']);
      c.updatePosition(onScreen: false);
      fetcher.succeed('a');
      async.flushMicrotasks();
      expect(fetcher.started, ['a', 'b']);
      c.release();
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.started, ['a', 'b']);
    });
  });

  test('leaving mid-flight aborts a large fetch, lets a small one finish', () {
    run((async) {
      final big = loader.acquire(req('big', size: 1024 * 1024))
        ..updatePosition(onScreen: true);
      final small = show('small');
      async.flushMicrotasks();
      big.release();
      small.release();
      async.flushMicrotasks();
      expect(fetcher.call('big').aborted, isTrue);
      expect(fetcher.call('small').aborted, isFalse);
      fetcher.succeed('small');
      async.flushMicrotasks();
      expect(loader.isCached('small', 'tx-small'), isTrue);
    });
  });

  test('waits for scroll to rest before starting', () {
    run((async) {
      loader.notifyScrolling();
      show('a');
      async.elapse(const Duration(milliseconds: 100));
      expect(fetcher.calls, isEmpty);
      loader.notifyScrolling();
      async.elapse(const Duration(milliseconds: 100));
      expect(fetcher.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 60));
      expect(fetcher.started, ['a']);
    });
  });

  test('order follows priority, not arrival', () {
    run((async) {
      loader.notifyScrolling();
      show('far', priority: 9);
      show('near', priority: 1);
      show('mid', priority: 5);
      show('last', priority: 20);
      async.elapse(const Duration(milliseconds: 200));
      expect(fetcher.started, ['near', 'mid']);
      fetcher.succeed('near');
      async.flushMicrotasks();
      expect(fetcher.started, ['near', 'mid', 'far']);
    });
  });

  test('a 429 pauses everything and resumes after Retry-After', () {
    run((async) {
      show('a', priority: 0);
      show('b', priority: 1);
      show('c', priority: 2);
      async.flushMicrotasks();
      fetcher.fail(
          'a', const GalleryRateLimited(retryAfter: Duration(seconds: 10)));
      async.flushMicrotasks();
      // b still in flight; finishing it must not start c during the pause.
      fetcher.succeed('b');
      async.elapse(const Duration(seconds: 9));
      expect(fetcher.started, ['a', 'b']);
      async.elapse(const Duration(seconds: 2));
      expect(fetcher.started.length, 4); // a again + c
      expect(fetcher.started.toSet(), {'a', 'b', 'c'});
    });
  });

  test('without Retry-After the pause backs off exponentially and is capped',
      () {
    run((async) {
      show('a');
      async.flushMicrotasks();
      fetcher.fail('a', const GalleryRateLimited());
      async.flushMicrotasks();
      // base 2s + up to 25% jitter
      async.elapse(const Duration(seconds: 1, milliseconds: 900));
      expect(fetcher.calls.length, 1);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls.length, 2);
      fetcher.fail('a', const GalleryRateLimited());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3, milliseconds: 900));
      expect(fetcher.calls.length, 2); // second pause is 4s+
      async.elapse(const Duration(seconds: 2));
      expect(fetcher.calls.length, 3);
    });
  });

  test('a huge Retry-After is capped', () {
    run((async) {
      show('a');
      async.flushMicrotasks();
      fetcher.fail(
          'a', const GalleryRateLimited(retryAfter: Duration(hours: 1)));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 59));
      expect(fetcher.calls.length, 1);
      async.elapse(const Duration(seconds: 2));
      expect(fetcher.calls.length, 2);
    });
  });

  test('other failures retry a bounded number of times then fail', () {
    run((async) {
      final h = show('a');
      for (var i = 0; i < 3; i++) {
        async.elapse(const Duration(seconds: 1));
        fetcher.fail('a', Exception('boom'));
        async.flushMicrotasks();
      }
      async.elapse(const Duration(seconds: 5));
      expect(fetcher.calls.length, 3); // 1 try + 2 retries
      expect(h.value.status, GalleryImageStatus.failed);
      expect(h.value.failure, GalleryFailureReason.fetchFailed);
    });
  });

  test('success yields a tile-sized provider; cached item is not refetched',
      () {
    run((async) {
      final h = show('a');
      async.flushMicrotasks();
      fetcher.succeed('a', 100);
      async.flushMicrotasks();
      expect(h.value.status, GalleryImageStatus.loaded);
      expect(h.value.image, isA<ResizeImage>());
      h.release();

      final again = loader.acquire(req('a'));
      expect(again.value.status, GalleryImageStatus.loaded);
      again.updatePosition(onScreen: true);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls.length, 1);
    });
  });

  test('two tiles for one image share a single fetch', () {
    run((async) {
      show('a');
      show('a');
      async.flushMicrotasks();
      expect(fetcher.calls.length, 1);
    });
  });

  test('cache evicts least recently used by bytes', () {
    run((async) {
      for (final id in ['a', 'b', 'c']) {
        final h = show(id);
        async.flushMicrotasks();
        fetcher.succeed(id, 400);
        async.flushMicrotasks();
        h.release();
      }
      // 1000 byte budget: a (oldest) evicted.
      expect(loader.isCached('a', 'tx-a'), isFalse);
      expect(loader.isCached('b', 'tx-b'), isTrue);
      expect(loader.isCached('c', 'tx-c'), isTrue);
      expect(loader.cacheSizeBytes, 800);
    });
  });

  test('no usable variant fails without a fetch', () {
    run((async) {
      final h = loader.acquire(req('a', variants: const []));
      h.updatePosition(onScreen: true);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls, isEmpty);
      expect(h.value.failure, GalleryFailureReason.noSource);
    });
  });

  test('private files never fetch an original', () {
    run((async) {
      const r = GalleryImageRequest(
        fileId: 'p',
        isPrivate: true,
        variants: [GalleryVariant(txId: 't', size: 10, width: 64, height: 64)],
        original:
            GalleryVariant(txId: 'o', size: 100, width: 4000, height: 3000),
        tileWidth: 300,
        tileHeight: 300,
        devicePixelRatio: 1,
      );
      loader.acquire(r).updatePosition(onScreen: true);
      async.flushMicrotasks();
      expect(fetcher.calls.single.target.variant.txId, 't');
      expect(fetcher.calls.single.target.isOriginal, isFalse);
    });
  });
}
