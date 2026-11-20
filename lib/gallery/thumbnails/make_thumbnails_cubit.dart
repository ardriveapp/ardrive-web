import 'dart:convert';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/drive_explorer/thumbnail/missing_thumbnails.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// About what Make thumbnails uploads per image, for the price shown before
/// it starts: a small thumbnail, a large one, and the file's new metadata.
const int estimatedSmallThumbnailBytes = 8 * 1024;
const int estimatedLargeThumbnailBytes = 50 * 1024;
const int estimatedMetadataBytes = 1536;

/// The items Make thumbnails writes for an image that lacks [missing].
List<int> estimatedItemSizes(MissingThumbnails missing) => switch (missing) {
      MissingThumbnails.all => const [
          estimatedSmallThumbnailBytes,
          estimatedLargeThumbnailBytes,
          estimatedMetadataBytes,
        ],
      MissingThumbnails.large => const [
          estimatedLargeThumbnailBytes,
          estimatedMetadataBytes,
        ],
      MissingThumbnails.none => const [],
    };

/// The images in a folder that lack thumbnails: what Make thumbnails makes.
/// Hidden files and uploads that failed are left alone.
Map<String, MissingThumbnails> imagesLackingThumbnails(
  Iterable<FileWithLicenseAndLatestRevisionTransactions> files,
) =>
    {
      for (final file in files)
        if (!file.isHidden && file.dataTx.status != 'failed')
          if (_missing(file) case final missing
              when missing != MissingThumbnails.none)
            file.id: missing,
    };

/// [imagesLackingThumbnails] for one folder's files.
Future<Map<String, MissingThumbnails>> imagesLackingThumbnailsInFolder(
  DriveDao driveDao, {
  required String driveId,
  required String folderId,
}) async =>
    imagesLackingThumbnails(await driveDao
        .filesInFolderWithLicenseAndRevisionTransactions(
          driveId: driveId,
          parentFolderId: folderId,
        )
        .get());

MissingThumbnails _missing(FileWithLicenseAndLatestRevisionTransactions file) {
  final json = file.thumbnail;
  List<Variant>? variants;
  if (json != null && json != 'null') {
    try {
      variants = Thumbnail.fromJson(jsonDecode(json)).variants;
    } catch (_) {
      variants = null;
    }
  }
  return missingThumbnailsOf(
    contentType: file.dataContentType,
    size: file.size,
    variants: variants,
  );
}

enum MakeThumbnailsPhase {
  /// Finding the images and reading the price.
  loading,

  /// Every image here has its thumbnails.
  nothingToDo,

  /// The images and the price, waiting for Make thumbnails.
  ready,

  /// Making them; [MakeThumbnailsState.made] of [MakeThumbnailsState.total].
  working,

  /// Stopping: the ones under way finish, no new one starts.
  stopping,

  /// Finished, stopped, or ended by a payment the allowance did not cover.
  done,
}

class MakeThumbnailsState extends Equatable {
  const MakeThumbnailsState({
    required this.phase,
    this.total = 0,
    this.made = 0,
    this.failed = 0,
    this.nothingToAdd = 0,
    this.loadFailed = false,
    this.summary,
    this.pricingFailed = false,
    this.paymentRequired = false,
    this.stopped = false,
  });

  final MakeThumbnailsPhase phase;

  /// Images that lack thumbnails.
  final int total;
  final int made;
  final int failed;

  /// Images that gave nothing more, such as ones too small for a large
  /// thumbnail.
  final int nothingToAdd;

  /// The folder's images could not be read.
  final bool loadFailed;

  /// The price, once read; null while it is read.
  final UploadReviewSummary? summary;
  final bool pricingFailed;

  /// Turbo refused a write: the allowance is used up and credits are short.
  final bool paymentRequired;

  /// Ended by Stop.
  final bool stopped;

  MakeThumbnailsState copyWith({
    MakeThumbnailsPhase? phase,
    int? total,
    int? made,
    int? failed,
    int? nothingToAdd,
    bool? loadFailed,
    UploadReviewSummary? summary,
    bool? pricingFailed,
    bool? paymentRequired,
    bool? stopped,
  }) =>
      MakeThumbnailsState(
        phase: phase ?? this.phase,
        total: total ?? this.total,
        made: made ?? this.made,
        failed: failed ?? this.failed,
        nothingToAdd: nothingToAdd ?? this.nothingToAdd,
        loadFailed: loadFailed ?? this.loadFailed,
        summary: summary ?? this.summary,
        pricingFailed: pricingFailed ?? this.pricingFailed,
        paymentRequired: paymentRequired ?? this.paymentRequired,
        stopped: stopped ?? this.stopped,
      );

  @override
  List<Object?> get props => [
        phase,
        total,
        made,
        failed,
        nothingToAdd,
        loadFailed,
        summary,
        pricingFailed,
        paymentRequired,
        stopped,
      ];
}

/// Make thumbnails for the images in one folder: finds those that lack them,
/// prices the writes the way every change is priced, then makes them a few
/// at a time. Stop lets the ones under way finish and keeps all that are
/// made.
class MakeThumbnailsCubit extends Cubit<MakeThumbnailsState> {
  MakeThumbnailsCubit({
    required bool isPrivate,
    required Future<Map<String, MissingThumbnails>> Function() findImages,
    required ThumbnailRepository thumbnails,
    required MetadataWriteCostReader costReader,
    required ProfileCubit profileCubit,
  })  : _findImages = findImages,
        _thumbnails = thumbnails,
        _costReader = costReader,
        _profileCubit = profileCubit,
        // A private image is downloaded and decrypted whole: one at a time.
        _workers = isPrivate ? 1 : 2,
        super(const MakeThumbnailsState(phase: MakeThumbnailsPhase.loading));

  final Future<Map<String, MissingThumbnails>> Function() _findImages;
  final ThumbnailRepository _thumbnails;
  final MetadataWriteCostReader _costReader;
  final ProfileCubit _profileCubit;
  final int _workers;

  Map<String, MissingThumbnails> _todo = const {};
  bool _stop = false;
  int _priceRead = 0;

  Future<void> load() async {
    emit(const MakeThumbnailsState(phase: MakeThumbnailsPhase.loading));
    try {
      _todo = {
        for (final e in (await _findImages()).entries)
          if (!_thumbnails.hasNothingToAdd(e.key)) e.key: e.value,
      };
    } catch (error, trace) {
      logger.e('Make thumbnails could not list the images', error, trace);
      if (!isClosed) {
        emit(const MakeThumbnailsState(
          phase: MakeThumbnailsPhase.done,
          loadFailed: true,
        ));
      }
      return;
    }
    if (isClosed) return;
    if (_todo.isEmpty) {
      emit(const MakeThumbnailsState(phase: MakeThumbnailsPhase.nothingToDo));
      return;
    }
    emit(MakeThumbnailsState(
      phase: MakeThumbnailsPhase.ready,
      total: _todo.length,
    ));
    await readPrice();
  }

  /// Reads the price again, as Add credits and Try again do.
  Future<void> readPrice() async {
    final read = ++_priceRead;
    final profile = _profileCubit.state;
    if (profile is! ProfileLoggedIn) return;
    UploadReviewSummary summary;
    var failed = false;
    try {
      final cost = await _costReader.read(
        itemSizes: [
          for (final missing in _todo.values) ...estimatedItemSizes(missing),
        ],
        wallet: profile.user.wallet,
        walletBalance: profile.user.walletBalance,
        refusedByTurbo: state.paymentRequired,
      );
      summary = cost.summary;
    } catch (error, trace) {
      logger.e('Could not price Make thumbnails', error, trace);
      summary = MetadataWriteCostReader.unavailable();
      failed = true;
    }
    if (isClosed || read != _priceRead) return;
    emit(state.copyWith(summary: summary, pricingFailed: failed));
  }

  Future<void> start() async {
    if (state.phase != MakeThumbnailsPhase.ready) return;
    final summary = state.summary;
    // Only what is free or paid for, as the review showed it.
    if (summary == null || !summary.isCovered) return;
    _stop = false;
    emit(state.copyWith(
      phase: MakeThumbnailsPhase.working,
      made: 0,
      failed: 0,
      paymentRequired: false,
    ));

    final queue = _todo.keys.toList();
    var made = 0;
    var failed = 0;
    // Images that gave nothing more, such as ones too small for a large
    // thumbnail: neither made nor failed.
    var nothingToAdd = 0;
    var paymentRequired = false;

    Future<void> worker() async {
      while (queue.isNotEmpty && !_stop) {
        final fileId = queue.removeAt(0);
        try {
          final added = await _thumbnails.uploadThumbnail(fileId: fileId);
          if (added) {
            made++;
          } else {
            nothingToAdd++;
          }
          _todo = Map.of(_todo)..remove(fileId);
        } catch (error) {
          if (isTurboPaymentError(error)) {
            paymentRequired = true;
            _stop = true;
          } else {
            logger.w('Make thumbnails: $fileId failed: $error');
            failed++;
          }
        }
        if (!isClosed) {
          emit(state.copyWith(
            made: made,
            failed: failed,
            nothingToAdd: nothingToAdd,
          ));
        }
      }
    }

    await Future.wait([for (var i = 0; i < _workers; i++) worker()]);
    if (isClosed) return;
    emit(state.copyWith(
      phase: MakeThumbnailsPhase.done,
      made: made,
      failed: failed,
      nothingToAdd: nothingToAdd,
      paymentRequired: paymentRequired,
      stopped: _stop && !paymentRequired,
    ));
  }

  /// Closed while working (a system back, say): nothing new starts, so no
  /// writes go on that no one sees.
  @override
  Future<void> close() {
    _stop = true;
    return super.close();
  }

  /// The ones under way finish; nothing new starts. What is made stays.
  void stop() {
    if (state.phase != MakeThumbnailsPhase.working) return;
    _stop = true;
    emit(state.copyWith(phase: MakeThumbnailsPhase.stopping));
  }
}
