import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/data/publication_uploader.dart';
import 'package:ardrive/publication/domain/publication_files.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:arweave/arweave.dart';
import 'package:http/http.dart' as http;

/// An image a publication has: new bytes to upload, or files an earlier
/// version already uploaded, by manifest path.
sealed class PublicationImage {
  const PublicationImage();
}

class NewPublicationImage extends PublicationImage {
  const NewPublicationImage(this.files);

  /// Manifest path to bytes: `icon-32.png`, `cover.jpg`...
  final Map<String, Uint8List> files;
}

class ExistingPublicationImage extends PublicationImage {
  const ExistingPublicationImage(this.files);

  /// Manifest path to transaction ID.
  final Map<String, String> files;
}

/// The snapshot a publication shows: one already published, with its tags,
/// or one to publish first.
sealed class PublicationSnapshotPlan {
  const PublicationSnapshotPlan();
}

class ReusedSnapshot extends PublicationSnapshotPlan {
  const ReusedSnapshot({required this.txId, required this.tags});

  final String txId;
  final Map<String, String> tags;
}

class NewSnapshot extends PublicationSnapshotPlan {
  const NewSnapshot(this.artifact);

  final PreparedDriveStateArtifact artifact;
}

/// Everything one publish writes, and how far it got: a failed publish is
/// tried again with the same job, which reuses what was already signed and
/// posted rather than paying for it twice.
class PublicationJob {
  PublicationJob({
    required this.publicationId,
    required this.driveId,
    required this.rootFolderId,
    required this.folderId,
    required this.owner,
    required this.ownerName,
    required this.title,
    required this.description,
    required this.keywords,
    required this.license,
    required this.icon,
    required this.cover,
    required this.social,
    required this.snapshot,
    required this.release,
    required this.files,
    required this.labels,
    required this.method,
  });

  final String publicationId;
  final String driveId;
  final String rootFolderId;

  /// Null for the whole drive.
  final String? folderId;
  final String owner;
  final String? ownerName;
  final String title;
  final String description;
  final List<String> keywords;
  final Map<String, Object>? license;
  final PublicationImage? icon;
  final PublicationImage? cover;

  /// Always set: the owner's card or the generated one.
  final PublicationImage social;
  final PublicationSnapshotPlan snapshot;
  final PublicationRelease release;

  /// What `files.html` lists.
  final List<PublicationListedFile> files;
  final PublicationLabels labels;
  final UploadMethod method;

  // Progress, kept for a retry.
  String? _snapshotTxId;
  Map<String, String>? _snapshotTags;
  List<_Signed>? _signed;
  final _posted = <String>{};
  String? _bundleTxId;
  String? _publishedAt;

  /// The manifest's ID once it is signed: the publication's link.
  String? get manifestTxId =>
      _signed?.where((s) => s.name == 'manifest').firstOrNull?.item.id;

  bool get snapshotIsNew => snapshot is NewSnapshot;
}

/// The words a publication's own files carry.
class PublicationLabels {
  const PublicationLabels({
    required this.filesPage,
    required this.openPage,
    required this.moreFiles,
  });

  final String filesPage;
  final String openPage;

  /// Holds `{count}`.
  final String moreFiles;
}

class _Signed {
  _Signed(this.name, this.item);

  final String name;
  final DataItem item;
}

enum PublicationStep { snapshot, files, publication, warmUp }

class PublicationFailure implements Exception {
  const PublicationFailure(this.step, this.message, {this.paidTxId});

  final PublicationStep step;
  final String message;

  /// Set when a transaction reached the network before the failure, so it is
  /// paid for whatever happened to its data.
  final String? paidTxId;

  @override
  String toString() => 'PublicationFailure($step): $message';
}

/// Publishes a drive or folder to the web (docs/PUBLICATIONS.md): the
/// snapshot when it is new, then the publication's files, then the manifest
/// that is its link.
class PublicationPublisher {
  PublicationPublisher({
    required PublicationUploader uploader,
    required DriveStateUploader driveStateUploader,
    required PublicationRepository repository,
    required String Function() gatewayUrl,
    http.Client? client,
    DateTime Function()? now,
  })  : _uploader = uploader,
        _driveStateUploader = driveStateUploader,
        _repository = repository,
        _gatewayUrl = gatewayUrl,
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final PublicationUploader _uploader;
  final DriveStateUploader _driveStateUploader;
  final PublicationRepository _repository;
  final String Function() _gatewayUrl;
  final http.Client _client;
  final DateTime Function() _now;

  /// The size in bytes of everything [job] would upload, its snapshot
  /// included when new: for the cost, before anything is signed.
  int sizeOf(PublicationJob job) {
    const placeholderId = 'PLACEHOLDER_TRANSACTION_ID_0000000000000000';
    final items = _items(
      job,
      snapshotTxId: placeholderId,
      snapshotTags: switch (job.snapshot) {
        ReusedSnapshot(:final tags) => tags,
        NewSnapshot() => const {},
      },
      idOf: (_) => placeholderId,
      publishedAt: publicationTimestamp(_now()),
    );
    var size = items.fold<int>(0, (sum, item) => sum + item.data.length);
    if (job.snapshot case NewSnapshot(:final artifact)) {
      size += artifact.sizeInBytes;
    }
    // Each data item's header: its signature, owner and tags.
    return size + items.length * 1100;
  }

  /// Runs [job], or resumes it, telling [onStep] what is under way.
  /// Throws [PublicationFailure].
  Future<PublishedVersion> publish(
    PublicationJob job,
    Wallet wallet, {
    void Function(PublicationStep step)? onStep,
  }) async {
    // 1. The snapshot, when it is new.
    if (job._snapshotTxId == null) {
      switch (job.snapshot) {
        case ReusedSnapshot(:final txId, :final tags):
          job._snapshotTxId = txId;
          job._snapshotTags = tags;
        case NewSnapshot(:final artifact):
          onStep?.call(PublicationStep.snapshot);
          final result =
              await _driveStateUploader.publish(artifact, method: job.method);
          if (!result.isPublished) {
            throw PublicationFailure(
              PublicationStep.snapshot,
              result.reason ?? 'The snapshot could not be published.',
              paidTxId: result.isUncertain ? result.txId : null,
            );
          }
          job._snapshotTxId = result.txId;
          job._snapshotTags = result.tags;
      }
    }

    // 2. Sign every file, which fixes their IDs, then post them.
    onStep?.call(PublicationStep.files);
    try {
      job._signed ??= await _sign(job, wallet);
    } catch (e) {
      logger.e('[publication] signing failed', e);
      throw const PublicationFailure(
        PublicationStep.files,
        'Your wallet did not sign the publication. Nothing was uploaded for '
        'it.',
      );
    }
    final signed = job._signed!;
    onStep?.call(PublicationStep.publication);
    try {
      if (job.method == UploadMethod.turbo) {
        for (final s in signed) {
          if (job._posted.contains(s.name)) continue;
          await _uploader.postToTurbo(s.item, wallet);
          job._posted.add(s.name);
        }
      } else if (job._bundleTxId == null) {
        await _uploader.postBundle(
          [for (final s in signed) s.item],
          wallet,
          onPosted: (txId) => job._bundleTxId = txId,
        );
      }
    } catch (e) {
      logger.e('[publication] posting failed', e);
      throw PublicationFailure(
        PublicationStep.publication,
        _postFailureMessage(e),
        paidTxId: job._bundleTxId,
      );
    }

    final version = PublishedVersion(
      txId: job.manifestTxId!,
      publicationId: job.publicationId,
      driveId: job.driveId,
      folderId: job.folderId,
      publishedAt: DateTime.parse(job._publishedAt!),
    );
    _repository.remember(version);

    // 3. Ask the gateway for the page once, so the first visitor does not
    // wait for it to fetch everything. A failure here changes nothing.
    if (job.method == UploadMethod.turbo) {
      onStep?.call(PublicationStep.warmUp);
      await _warmUp(version.txId);
    }
    return version;
  }

  String _postFailureMessage(Object e) {
    final text = '$e';
    if (text.contains('402') || text.contains('PaymentRequired')) {
      return 'Turbo declined the payment. Add credits or pay with AR, then '
          'try again.';
    }
    return 'The upload did not finish. Try again: what was already sent is '
        'not sent or paid for twice.';
  }

  Future<List<_Signed>> _sign(PublicationJob job, Wallet wallet) async {
    job._publishedAt ??= publicationTimestamp(_now());
    final signed = <_Signed>[];
    final ids = <String, String>{
      'snapshot': job._snapshotTxId!,
      for (final image in [job.icon, job.cover, job.social])
        if (image is ExistingPublicationImage) ...image.files,
    };
    // Images first: index.html names the social card by its own ID.
    for (final item in _imageItems(job)) {
      final dataItem = await _uploader.sign(item, wallet);
      signed.add(_Signed(item.name, dataItem));
      ids[item.name] = dataItem.id;
    }
    for (final item in _pageItems(
      job,
      snapshotTxId: job._snapshotTxId!,
      snapshotTags: job._snapshotTags!,
      socialId: ids['social.jpg']!,
      publishedAt: job._publishedAt!,
    )) {
      final dataItem = await _uploader.sign(item, wallet);
      signed.add(_Signed(item.name, dataItem));
      ids[item.name] = dataItem.id;
    }
    final manifest = _manifestItem(job, ids);
    signed.add(_Signed('manifest', await _uploader.sign(manifest, wallet)));
    return signed;
  }

  List<PublicationItem> _items(
    PublicationJob job, {
    required String snapshotTxId,
    required Map<String, String> snapshotTags,
    required String Function(String name) idOf,
    required String publishedAt,
  }) {
    final images = _imageItems(job);
    final ids = <String, String>{
      'snapshot': snapshotTxId,
      for (final image in [job.icon, job.cover, job.social])
        if (image is ExistingPublicationImage) ...image.files,
      for (final item in images) item.name: idOf(item.name),
    };
    final pages = _pageItems(
      job,
      snapshotTxId: snapshotTxId,
      snapshotTags: snapshotTags,
      socialId: ids['social.jpg']!,
      publishedAt: publishedAt,
    );
    for (final item in pages) {
      ids[item.name] = idOf(item.name);
    }
    return [...images, ...pages, _manifestItem(job, ids)];
  }

  List<PublicationItem> _imageItems(PublicationJob job) {
    final part = publicationPartTags(job.publicationId);
    return [
      for (final image in [job.icon, job.cover, job.social])
        if (image is NewPublicationImage)
          for (final MapEntry(key: name, value: bytes) in image.files.entries)
            PublicationItem(
              name: name,
              data: bytes,
              contentType: name.endsWith('.png') ? 'image/png' : 'image/jpeg',
              tags: part,
            ),
    ];
  }

  List<PublicationItem> _pageItems(
    PublicationJob job, {
    required String snapshotTxId,
    required Map<String, String> snapshotTags,
    required String socialId,
    required String publishedAt,
  }) {
    final part = publicationPartTags(job.publicationId);
    final gateway = _gatewayUrl();
    final hasIcon = job.icon != null;
    final publicationJson = buildPublicationJson(
      driveId: job.driveId,
      rootFolderId: job.rootFolderId,
      folderId: job.folderId,
      privacy: DrivePrivacyTag.public,
      owner: job.owner,
      ownerName: job.ownerName,
      snapshotTxId: snapshotTxId,
      snapshotTags: snapshotTags,
      title: job.title,
      description: job.description,
      keywords: job.keywords,
      license: job.license,
      images: {
        if (hasIcon) 'icon': 'icon-512.png',
        'social': 'social.jpg',
        if (job.cover != null) 'cover': 'cover.jpg',
      },
      publishedAt: publishedAt,
      viewer: (
        release: job.release.version ?? 'unknown',
        manifest: job.release.manifestId,
      ),
    );
    final indexHtml = buildPublicationIndexHtml(
      job.release.indexHtml,
      title: job.title,
      description: job.description,
      icons: hasIcon ? (small: 'icon-32.png', touch: 'icon-180.png') : null,
      socialImageUrl: '$gateway/$socialId',
      filesPageLabel: job.labels.filesPage,
    );
    final files = job.files;
    PublicationItem text(String name, String content, String type) =>
        PublicationItem(
          name: name,
          data: Uint8List.fromList(utf8.encode(content)),
          contentType: type,
          tags: part,
        );
    return [
      text('publication.json', publicationJson, 'application/json'),
      text('index.html', indexHtml, 'text/html'),
      text(
        'files.html',
        buildPublicationFilesHtml(
          title: job.title,
          files: files,
          gateway: gateway,
          openLabel: job.labels.openPage,
          moreLabel: job.labels.moreFiles,
        ),
        'text/html',
      ),
      text(
        'sitemap.xml',
        buildPublicationSitemap(files: files, gateway: gateway),
        'application/xml',
      ),
    ];
  }

  PublicationItem _manifestItem(PublicationJob job, Map<String, String> ids) =>
      PublicationItem(
        name: 'manifest',
        data: Uint8List.fromList(
          utf8.encode(buildPublicationManifest(job.release.manifest, ids)),
        ),
        contentType: 'application/x.arweave-manifest+json',
        tags: [
          ...publicationEntityTags(
            driveId: job.driveId,
            publicationId: job.publicationId,
            folderId: job.folderId,
          ),
          for (final keyword in job.keywords) (name: 'Keyword', value: keyword),
        ],
      );

  Future<void> _warmUp(String manifestTxId) async {
    final base = _gatewayUrl();
    for (final path in ['', 'publication.json']) {
      try {
        await _client
            .get(Uri.parse('$base/$manifestTxId/$path'))
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        logger.w('[publication] warming $path failed: $e');
      }
    }
  }
}
