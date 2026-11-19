import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What a fetch is asked for. Public and private files both come through
/// here; the fetcher decides how (gateway read, or download + decrypt).
class GalleryFetchTarget {
  const GalleryFetchTarget({
    required this.fileId,
    required this.variant,
    required this.isPrivate,
    required this.isOriginal,
  });

  final String fileId;
  final GalleryVariant variant;
  final bool isPrivate;
  final bool isOriginal;
}

/// Gets the (decrypted) bytes of one rendition. Injected so the loader is
/// testable.
abstract class GalleryImageFetcher {
  /// [cancelWhen] completes if the loader no longer wants the bytes; a fetcher
  /// that can abort should. One that cannot may ignore it.
  ///
  /// Throw [GalleryRateLimited] on HTTP 429/503 so the loader pauses.
  Future<Uint8List> fetch(
    GalleryFetchTarget target, {
    required Future<void> cancelWhen,
  });
}

/// The gateway said slow down (429 or 503).
class GalleryRateLimited implements Exception {
  const GalleryRateLimited({this.retryAfter});

  /// From the Retry-After header, when the gateway sent one.
  final Duration? retryAfter;

  @override
  String toString() => 'GalleryRateLimited(retryAfter: $retryAfter)';
}

class GalleryLoaderConfig {
  const GalleryLoaderConfig({
    this.maxConcurrent = 5,
    this.idleDelay = const Duration(milliseconds: 150),
    this.maxOriginalBytes = galleryMaxOriginalBytes,
    this.cacheBytes = 64 * 1024 * 1024,
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    this.backoffBase = const Duration(seconds: 2),
    this.backoffCap = const Duration(seconds: 60),
    this.cancelInFlightAboveBytes = 256 * 1024,
  });

  /// The app's existing data-fetch setting.
  factory GalleryLoaderConfig.fromAppConfig(AppConfig config) =>
      GalleryLoaderConfig(
        maxConcurrent: math.max(1, config.maxConcurrentDataFetches),
      );

  final int maxConcurrent;

  /// How long scrolling must rest before new work starts.
  final Duration idleDelay;
  final int maxOriginalBytes;

  /// Budget for encoded bytes kept for the session.
  final int cacheBytes;

  /// Retries after the first attempt for failures that are not rate limits.
  final int maxRetries;
  final Duration retryDelay;
  final Duration backoffBase;
  final Duration backoffCap;

  /// A tile that leaves the screen mid-fetch aborts the fetch only when the
  /// rendition is larger than this; small thumbnails finish into the cache.
  final int cancelInFlightAboveBytes;
}

/// A tile's request: which file, which renditions exist, and how big the tile
/// is.
class GalleryImageRequest {
  const GalleryImageRequest({
    required this.fileId,
    required this.isPrivate,
    required this.variants,
    required this.tileWidth,
    required this.tileHeight,
    required this.devicePixelRatio,
    this.original,
  });

  final String fileId;
  final bool isPrivate;
  final List<GalleryVariant> variants;
  final GalleryVariant? original;

  /// Logical pixels.
  final double tileWidth;
  final double tileHeight;
  final double devicePixelRatio;

  double get tileWidthPx => tileWidth * devicePixelRatio;
  double get tileHeightPx => tileHeight * devicePixelRatio;
}

enum GalleryImageStatus { loading, loaded, failed }

enum GalleryFailureReason { noSource, fetchFailed }

@immutable
class GalleryImageState {
  const GalleryImageState.loading()
      : status = GalleryImageStatus.loading,
        image = null,
        failure = null;

  const GalleryImageState.loaded(ImageProvider this.image)
      : status = GalleryImageStatus.loaded,
        failure = null;

  const GalleryImageState.failed(GalleryFailureReason this.failure)
      : status = GalleryImageStatus.failed,
        image = null;

  final GalleryImageStatus status;

  /// Set when [status] is loaded. Already sized for the tile.
  final ImageProvider? image;
  final GalleryFailureReason? failure;

  @override
  bool operator ==(Object other) =>
      other is GalleryImageState &&
      other.status == status &&
      other.image == image &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(status, image, failure);
}

/// A tile's view of one image. Listen to it; tell it where the tile is.
class GalleryImageHandle implements ValueListenable<GalleryImageState> {
  GalleryImageHandle._(this._loader, this._entry);

  final GalleryImageLoader _loader;
  final _Entry _entry;
  bool _released = false;
  bool _onScreen = false;
  double _priority = 0;

  @override
  GalleryImageState get value => _entry.notifier.value;

  @override
  void addListener(VoidCallback listener) =>
      _entry.notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _entry.notifier.removeListener(listener);

  /// Report visibility. Nothing starts until the tile is on screen. A lower
  /// [priority] starts first (distance from the viewport; the caller can
  /// favour the scroll direction by making those tiles nearer).
  void updatePosition({required bool onScreen, double priority = 0}) {
    if (_released) return;
    _onScreen = onScreen;
    _priority = priority;
    _loader._positionChanged(_entry);
  }

  /// Try again after a failure.
  void retry() {
    if (_released) return;
    _loader._retry(_entry);
  }

  /// The tile is gone. Cancels queued work; see
  /// [GalleryLoaderConfig.cancelInFlightAboveBytes] for in-flight work.
  void release() {
    if (_released) return;
    _released = true;
    _onScreen = false;
    _loader._release(_entry, this);
  }
}

class _Entry {
  _Entry(this.key, this.target, this.tileWidthPx);

  final String key;
  final GalleryFetchTarget? target;
  final double tileWidthPx;
  final ValueNotifier<GalleryImageState> notifier =
      ValueNotifier(const GalleryImageState.loading());
  final List<GalleryImageHandle> handles = [];
  int order = 0;
  int attempts = 0;
  DateTime? notBefore;
  bool inFlight = false;
  bool queued = false;
  Completer<void>? cancel;
  bool disposed = false;
}

/// One shared, polite queue for gallery images.
///
/// Requests come per tile ([acquire]); only on-screen tiles are started, in
/// priority order, at most [GalleryLoaderConfig.maxConcurrent] at a time and
/// only once scrolling has rested ([notifyScrolling]). A 429/503 pauses the
/// whole queue. Fetched bytes sit in an LRU by size, so nothing is fetched
/// twice in a session, and images are handed out as [ResizeImage]s so they
/// decode at tile size.
class GalleryImageLoader {
  GalleryImageLoader({
    required GalleryImageFetcher fetcher,
    this.config = const GalleryLoaderConfig(),
    math.Random? random,
  })  : _fetcher = fetcher,
        _random = random ?? math.Random();

  final GalleryImageFetcher _fetcher;
  final GalleryLoaderConfig config;
  final math.Random _random;

  final Map<String, _Entry> _entries = {};
  // Insertion order == recency (re-inserted on hit).
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  int _cacheSize = 0;

  int _inFlight = 0;
  int _counter = 0;
  bool _idle = true;
  Timer? _idleTimer;
  Timer? _wakeTimer;
  DateTime? _pausedUntil;
  int _rateLimitHits = 0;
  bool _disposed = false;

  /// Requests currently being fetched. For tests and diagnostics.
  int get inFlightCount => _inFlight;

  /// Bytes held by the memory cache.
  int get cacheSizeBytes => _cacheSize;

  bool isCached(String fileId, String txId) =>
      _cache.containsKey(_key(fileId, txId));

  /// Ask for an image. Starts nothing until [GalleryImageHandle.updatePosition]
  /// reports the tile on screen (unless the bytes are already cached).
  GalleryImageHandle acquire(GalleryImageRequest request) {
    final choice = chooseGalleryVariant(
      variants: request.variants,
      original: request.original,
      tileWidthPx: request.tileWidthPx,
      tileHeightPx: request.tileHeightPx,
      isPrivate: request.isPrivate,
      maxOriginalBytes: config.maxOriginalBytes,
    );

    if (choice == null) {
      final entry = _Entry('${request.fileId}/-', null, request.tileWidthPx);
      entry.notifier.value =
          const GalleryImageState.failed(GalleryFailureReason.noSource);
      final handle = GalleryImageHandle._(this, entry);
      entry.handles.add(handle);
      return handle;
    }

    final key = _key(request.fileId, choice.variant.txId);
    final cached = _cacheGet(key);
    if (cached != null) {
      // Standalone: already loaded, nothing to schedule or share.
      final entry = _Entry(key, null, request.tileWidthPx);
      entry.notifier.value =
          GalleryImageState.loaded(_provider(cached, request.tileWidthPx));
      final handle = GalleryImageHandle._(this, entry);
      entry.handles.add(handle);
      return handle;
    }

    var entry = _entries[key];
    if (entry == null) {
      entry = _Entry(
        key,
        GalleryFetchTarget(
          fileId: request.fileId,
          variant: choice.variant,
          isPrivate: request.isPrivate,
          isOriginal: choice.isOriginal,
        ),
        request.tileWidthPx,
      );
      _entries[key] = entry;
    }

    final handle = GalleryImageHandle._(this, entry);
    entry.handles.add(handle);
    return handle;
  }

  /// Tell the loader scrolling is happening (call on every scroll update or
  /// scrubber move). New work waits for [GalleryLoaderConfig.idleDelay] of rest.
  void notifyScrolling() {
    if (_disposed) return;
    _idle = false;
    _idleTimer?.cancel();
    _idleTimer = Timer(config.idleDelay, () {
      _idle = true;
      _pump();
    });
  }

  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _wakeTimer?.cancel();
    for (final e in _entries.values) {
      _abort(e);
    }
    _entries.clear();
    _cache.clear();
    _cacheSize = 0;
  }

  // ---- handle callbacks ----

  void _positionChanged(_Entry entry) {
    if (_disposed) return;
    final state = entry.notifier.value;
    if (state.status == GalleryImageStatus.loading &&
        !entry.inFlight &&
        entry.handles.any((h) => h._onScreen)) {
      entry.queued = true;
      if (entry.order == 0) entry.order = ++_counter;
    } else if (!entry.inFlight) {
      entry.queued = false;
    } else if (!entry.handles.any((h) => h._onScreen)) {
      _maybeAbort(entry);
    }
    _pump();
  }

  void _retry(_Entry entry) {
    if (entry.notifier.value.status != GalleryImageStatus.failed ||
        entry.target == null) {
      return;
    }
    entry.attempts = 0;
    entry.notBefore = null;
    entry.notifier.value = const GalleryImageState.loading();
    _positionChanged(entry);
  }

  void _release(_Entry entry, GalleryImageHandle handle) {
    entry.handles.remove(handle);
    if (entry.handles.isNotEmpty) {
      _positionChanged(entry);
      return;
    }
    entry.queued = false;
    if (entry.inFlight) {
      _maybeAbort(entry);
      return; // finish handler cleans up
    }
    _dispose(entry);
    _pump();
  }

  void _maybeAbort(_Entry entry) {
    final target = entry.target;
    if (target != null &&
        target.variant.size > config.cancelInFlightAboveBytes) {
      _abort(entry);
    }
  }

  void _abort(_Entry entry) {
    final c = entry.cancel;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _dispose(_Entry entry) {
    if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
    entry.disposed = true;
    // Defer so a listener removing itself in the same turn is not disturbed.
    scheduleMicrotask(entry.notifier.dispose);
  }

  // ---- scheduling ----

  void _pump() {
    if (_disposed) return;
    final now = clock.now();

    final pausedUntil = _pausedUntil;
    if (pausedUntil != null) {
      if (now.isBefore(pausedUntil)) {
        _wakeAfter(pausedUntil.difference(now));
        return;
      }
      _pausedUntil = null;
    }
    if (!_idle) return; // the idle timer pumps again

    Duration? wait;
    while (_inFlight < config.maxConcurrent) {
      _Entry? best;
      for (final e in _entries.values) {
        if (!e.queued || e.inFlight) continue;
        final nb = e.notBefore;
        if (nb != null && now.isBefore(nb)) {
          final d = nb.difference(now);
          if (wait == null || d < wait) wait = d;
          continue;
        }
        if (best == null || _before(e, best)) best = e;
      }
      if (best == null) break;
      _start(best);
    }
    if (wait != null) _wakeAfter(wait);
  }

  bool _before(_Entry a, _Entry b) {
    final pa = a.handles.where((h) => h._onScreen).map((h) => h._priority);
    final pb = b.handles.where((h) => h._onScreen).map((h) => h._priority);
    final va = pa.isEmpty ? double.infinity : pa.reduce(math.min);
    final vb = pb.isEmpty ? double.infinity : pb.reduce(math.min);
    if (va != vb) return va < vb;
    return a.order < b.order;
  }

  void _wakeAfter(Duration d) {
    _wakeTimer?.cancel();
    _wakeTimer = Timer(d, _pump);
  }

  Future<void> _start(_Entry entry) async {
    entry.inFlight = true;
    entry.queued = false;
    entry.cancel = Completer<void>();
    _inFlight++;
    final cancel = entry.cancel!;

    Uint8List? bytes;
    Object? error;
    try {
      bytes = await _fetcher.fetch(entry.target!, cancelWhen: cancel.future);
    } catch (e) {
      error = e;
    }

    _inFlight--;
    entry.inFlight = false;
    final aborted = cancel.isCompleted;
    entry.cancel = null;
    if (_disposed) return;

    if (error == null && bytes != null) {
      _rateLimitHits = 0;
      _cachePut(entry.key, bytes);
      if (entry.handles.isEmpty) {
        _dispose(entry);
      } else {
        entry.notifier.value =
            GalleryImageState.loaded(_provider(bytes, entry.tileWidthPx));
        if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
      }
    } else if (aborted && entry.handles.isEmpty) {
      _dispose(entry);
    } else if (error is GalleryRateLimited) {
      _backoff(error);
      entry.queued = entry.handles.isNotEmpty;
      if (entry.handles.isEmpty) _dispose(entry);
    } else {
      entry.attempts++;
      if (entry.attempts > config.maxRetries) {
        if (entry.handles.isEmpty) {
          _dispose(entry);
        } else {
          entry.notifier.value =
              const GalleryImageState.failed(GalleryFailureReason.fetchFailed);
        }
      } else if (entry.handles.isEmpty) {
        _dispose(entry);
      } else {
        entry.queued = true;
        entry.notBefore = clock.now().add(config.retryDelay * entry.attempts);
      }
    }
    _pump();
  }

  void _backoff(GalleryRateLimited e) {
    Duration delay;
    final ra = e.retryAfter;
    if (ra != null) {
      delay = ra > config.backoffCap ? config.backoffCap : ra;
    } else {
      final exp = config.backoffBase * math.pow(2, _rateLimitHits).toInt();
      final capped = exp > config.backoffCap ? config.backoffCap : exp;
      final jitterMs =
          (capped.inMilliseconds * 0.25 * _random.nextDouble()).round();
      delay = capped + Duration(milliseconds: jitterMs);
    }
    _rateLimitHits++;
    final until = clock.now().add(delay);
    final current = _pausedUntil;
    if (current == null || until.isAfter(current)) _pausedUntil = until;
  }

  // ---- cache ----

  static String _key(String fileId, String txId) => '$fileId/$txId';

  ImageProvider _provider(Uint8List bytes, double widthPx) => ResizeImage(
        MemoryImage(bytes),
        width: math.max(1, widthPx.round()),
        allowUpscaling: false,
      );

  Uint8List? _cacheGet(String key) {
    final v = _cache.remove(key);
    if (v != null) _cache[key] = v;
    return v;
  }

  void _cachePut(String key, Uint8List bytes) {
    final old = _cache.remove(key);
    if (old != null) _cacheSize -= old.length;
    if (bytes.length > config.cacheBytes) return;
    _cache[key] = bytes;
    _cacheSize += bytes.length;
    while (_cacheSize > config.cacheBytes && _cache.length > 1) {
      final oldest = _cache.keys.first;
      _cacheSize -= _cache.remove(oldest)!.length;
    }
  }
}
