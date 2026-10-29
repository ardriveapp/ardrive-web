import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show EntityTag, EntityTypeTag;
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;

/// One version of a publication: a Publication entity (docs/ArweaveFS.md,
/// "Publication"), which is the manifest a link opens.
class PublishedVersion extends Equatable {
  const PublishedVersion({
    required this.txId,
    required this.publicationId,
    required this.driveId,
    required this.scope,
    required this.publishedAt,
    this.minedAtHeight,
  });

  final String txId;
  final String publicationId;
  final String driveId;

  /// What it shows: the whole drive, one folder or one file. Never read as
  /// "no folder means the drive": a file page has no folder either.
  final PublicationScope scope;

  /// Its `Unix-Time`.
  final DateTime publishedAt;

  /// Null while it is not in a block yet.
  final int? minedAtHeight;

  @override
  List<Object?> get props =>
      [txId, publicationId, driveId, scope, publishedAt, minedAtHeight];
}

/// A publication and its versions, newest first.
class Publication extends Equatable {
  const Publication(this.versions);

  final List<PublishedVersion> versions;

  PublishedVersion get latest => versions.first;
  String get id => latest.publicationId;
  PublicationScope get scope => latest.scope;
  List<PublishedVersion> get earlier => versions.sublist(1);

  @override
  List<Object?> get props => [versions];
}

/// What a version holds: its settings and the transaction behind each of its
/// own paths (images, snapshot), read back to publish an update.
class PublishedContent {
  const PublishedContent({
    required this.config,
    required this.paths,
    this.keywords = const [],
    this.generatedCard = false,
  });

  final PublicationConfig config;

  /// Its `keywords`, which the viewer does not read.
  final List<String> keywords;

  /// Whether its social card is the one ArDrive drew.
  final bool generatedCard;

  /// The publication's own paths (not the release's), by transaction ID.
  final Map<String, String> paths;
}

/// The ArDrive release a publication runs: its manifest, `index.html` and
/// version.
/// Where a release says which publications it opens.
const publicationCapabilitiesPath = 'publication-capabilities.json';

class PublicationRelease {
  const PublicationRelease({
    required this.manifestId,
    required this.manifest,
    required this.indexHtml,
    required this.version,
    this.publicationVersion = 1,
  });

  final String manifestId;
  final Map<String, dynamic> manifest;
  final String indexHtml;
  final String? version;

  /// The newest `publication.json` version the release opens, from its
  /// `publication-capabilities.json`; 1 for a release built before it.
  final int publicationVersion;

  /// Whether the release opens file pages.
  bool get opensFilePages =>
      publicationVersion >= PublicationConfig.fileScopeVersion;
}

class PublicationReadException implements Exception {
  const PublicationReadException(this.message);

  final String message;

  @override
  String toString() => 'PublicationReadException: $message';
}

/// Finds a drive's publications and reads them back, through the gateway the
/// app's settings name.
///
/// Publications are found by GraphQL, as drive states are, which can lag a
/// fresh upload by minutes. A version this session published is remembered
/// here and counted at once, so the owner sees it the moment it is done.
class PublicationRepository {
  PublicationRepository({
    required GraphQLRetry graphQLRetry,
    required String Function() gatewayUrl,
    http.Client? client,
  })  : _graphQLRetry = graphQLRetry,
        _gatewayUrl = gatewayUrl,
        _client = client ?? http.Client();

  final GraphQLRetry _graphQLRetry;
  final String Function() _gatewayUrl;
  final http.Client _client;

  /// What this session published, by the wallet that published it: one tab
  /// can sign out and in as someone else.
  final _justPublished = <({String owner, PublishedVersion version})>[];
  final _changes = StreamController<String>.broadcast();

  /// The drive ID of every drive whose publications changed this session.
  Stream<String> get changes => _changes.stream;

  void remember(PublishedVersion version, {required String owner}) {
    _justPublished.add((owner: owner, version: version));
    _changes.add(version.driveId);
  }

  /// Every publication [ownerAddress] made, by drive ID, each list newest
  /// first. Throws [PublicationReadException] when GraphQL cannot answer:
  /// "none" must not be claimed on a failure.
  Future<Map<String, List<Publication>>> publicationsOfOwner(
    String ownerAddress,
  ) async {
    final found = <String, PublishedVersion>{};
    var cursor = '';
    var exhausted = false;
    for (var page = 0; page < 20; page++) {
      final OwnerPublications$Query$TransactionConnection transactions;
      try {
        final response = await _graphQLRetry.execute(
          OwnerPublicationsQuery(
            variables: OwnerPublicationsArguments(
              after: cursor,
              ownerAddress: ownerAddress,
            ),
          ),
        );
        final data = response.data;
        if (data == null) {
          throw const PublicationReadException('GraphQL returned no data');
        }
        transactions = data.transactions;
      } on PublicationReadException {
        rethrow;
      } catch (e) {
        throw PublicationReadException('GraphQL failed: $e');
      }
      for (final edge in transactions.edges) {
        final version = _toVersion(edge.node, ownerAddress);
        if (version != null) found[version.txId] = version;
      }
      if (transactions.edges.isEmpty || !transactions.pageInfo.hasNextPage) {
        exhausted = true;
        break;
      }
      cursor = transactions.edges.last.cursor;
    }
    // A list cut off at the page cap could leave a publication out, and the
    // app would then offer to publish it again: say it could not check.
    if (!exhausted) {
      throw const PublicationReadException(
          'more publications than can be listed');
    }
    for (final (:owner, :version) in _justPublished) {
      if (owner == ownerAddress) found.putIfAbsent(version.txId, () => version);
    }
    final byDrive = <String, List<PublishedVersion>>{};
    for (final version in found.values) {
      byDrive.putIfAbsent(version.driveId, () => []).add(version);
    }
    return {
      for (final MapEntry(:key, :value) in byDrive.entries)
        key: groupPublications(value),
    };
  }

  PublishedVersion? _toVersion(
    TransactionCommonMixin node,
    String ownerAddress,
  ) {
    final tags = <String, String>{};
    for (final tag in node.tags) {
      tags.putIfAbsent(tag.name, () => tag.value);
    }
    // The query asked for these; the indexer is not trusted to have obeyed.
    final driveId = tags[EntityTag.driveId];
    if (node.owner.address != ownerAddress ||
        tags[EntityTag.entityType] != EntityTypeTag.publication ||
        driveId == null) {
      return null;
    }
    final publicationId = tags[EntityTag.publicationId];
    final scopeTag = tags[EntityTag.publicationScope];
    final unixTime = int.tryParse(tags[EntityTag.unixTime] ?? '');
    if (publicationId == null || scopeTag == null || unixTime == null) {
      return null;
    }
    final PublicationScope scope;
    switch (scopeTag) {
      case 'drive':
        scope = const PublicationDriveScope();
      case 'file':
        final fileId = tags[EntityTag.fileId];
        if (fileId == null) return null;
        scope = PublicationFileScope(fileId);
      default:
        scope = PublicationFolderScope(scopeTag);
    }
    return PublishedVersion(
      txId: node.id,
      publicationId: publicationId,
      driveId: driveId,
      scope: scope,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(unixTime * 1000),
      minedAtHeight: node.block?.height,
    );
  }

  /// Reads back what [version] holds. Throws [PublicationReadException].
  Future<PublishedContent> readContent(String manifestTxId) async {
    final manifest = await _readJson(manifestTxId);
    final paths = (manifest['paths'] as Map?)?.cast<String, dynamic>() ?? {};
    String? idOf(String path) => (paths[path] as Map?)?['id'] as String?;
    final configId = idOf('publication.json');
    if (configId == null) {
      throw const PublicationReadException('no publication.json');
    }
    final PublicationConfig config;
    final String text;
    try {
      text = utf8.decode(await _read(configId));
      config = PublicationConfig.parse(text);
    } on PublicationConfigException catch (e) {
      throw PublicationReadException('publication.json: $e');
    } on FormatException catch (e) {
      throw PublicationReadException('publication.json: ${e.message}');
    }
    final raw = json.decode(text) as Map;
    final keywords = raw['keywords'];
    return PublishedContent(
      config: config,
      generatedCard: raw['generatedSocialCard'] == true,
      keywords: keywords is List ? [...keywords.whereType<String>()] : const [],
      paths: {
        for (final path in _ownPaths)
          if (idOf(path) case final id?) path: id,
      },
    );
  }

  static const _ownPaths = [
    'snapshot',
    'icon-32.png',
    'icon-180.png',
    'icon-512.png',
    'cover.jpg',
    'social.jpg',
  ];

  /// The release [viewer] names: a manifest ID as it is, or an ArNS name
  /// read through the gateway for the release it points at.
  Future<PublicationRelease> readRelease(String viewer) async {
    final manifestId = _isTxId(viewer) ? viewer : await _resolveName(viewer);
    final manifest = await _readJson(manifestId);
    if (manifest['manifest'] != 'arweave/paths') {
      throw PublicationReadException('$manifestId is not a path manifest');
    }
    final paths = (manifest['paths'] as Map?)?.cast<String, dynamic>() ?? {};
    final indexId = (paths['index.html'] as Map?)?['id'] as String?;
    if (indexId == null) {
      throw PublicationReadException('$manifestId has no index.html');
    }
    final versionId = (paths['version.json'] as Map?)?['id'] as String?;
    String? version;
    if (versionId != null) {
      try {
        version = (await _readJson(versionId))['version'] as String?;
      } catch (e) {
        logger.w('[publication] the release has an unreadable version.json');
      }
    }
    var publicationVersion = 1;
    final capabilitiesId =
        (paths[publicationCapabilitiesPath] as Map?)?['id'] as String?;
    if (capabilitiesId != null) {
      try {
        final declared =
            (await _readJson(capabilitiesId))['publicationVersion'];
        if (declared is int && declared > 1) publicationVersion = declared;
      } catch (e) {
        logger.w('[publication] the release has unreadable capabilities');
      }
    }
    return PublicationRelease(
      manifestId: manifestId,
      manifest: manifest,
      indexHtml: utf8.decode(await _read(indexId)),
      version: version,
      publicationVersion: publicationVersion,
    );
  }

  /// Bytes of a file in [driveId] or anywhere else, by its data transaction:
  /// an image the owner chooses from their drive.
  Future<Uint8List> readData(String txId) => _read(txId);

  Future<String> _resolveName(String name) async {
    final gateway = Uri.parse(_gatewayUrl());
    final uri = gateway.replace(host: '$name.${gateway.host}', path: '/');
    final http.Response response;
    try {
      response = await _client.head(uri);
    } catch (e) {
      throw PublicationReadException('could not resolve $name: $e');
    }
    final id = response.headers['x-arns-resolved-id'];
    if (id == null || !_isTxId(id)) {
      throw PublicationReadException(
          '$name did not resolve on ${gateway.host}');
    }
    return id;
  }

  Future<Map<String, dynamic>> _readJson(String txId) async {
    final Object? value;
    try {
      value = json.decode(utf8.decode(await _read(txId)));
    } on FormatException catch (e) {
      throw PublicationReadException('$txId is not JSON: ${e.message}');
    }
    if (value is! Map<String, dynamic>) {
      throw PublicationReadException('$txId is not a JSON object');
    }
    return value;
  }

  Future<Uint8List> _read(String txId) async {
    final uri = Uri.parse('${_gatewayUrl()}/raw/$txId');
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (e) {
      throw PublicationReadException('could not fetch $txId: $e');
    }
    if (response.statusCode != 200) {
      throw PublicationReadException(
          'fetching $txId: HTTP ${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    // Releases are uploaded gzipped with a Content-Encoding tag; a gateway
    // that drops the header hands over the compressed bytes.
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
    }
    return bytes;
  }

  static bool _isTxId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);
}

/// [versions] grouped by publication, each newest first, the publications
/// by their latest version, newest first. Newest is the highest block, with
/// versions not in a block yet above all, and `Unix-Time` breaking a tie.
List<Publication> groupPublications(Iterable<PublishedVersion> versions) {
  int newestFirst(PublishedVersion a, PublishedVersion b) {
    final ah = a.minedAtHeight, bh = b.minedAtHeight;
    if (ah != bh) {
      if (ah == null) return -1;
      if (bh == null) return 1;
      return bh.compareTo(ah);
    }
    return b.publishedAt.compareTo(a.publishedAt);
  }

  final byId = <String, List<PublishedVersion>>{};
  for (final version in versions) {
    byId.putIfAbsent(version.publicationId, () => []).add(version);
  }
  final publications = [
    for (final list in byId.values)
      // Every version keeps the first version's scope (docs/ArweaveFS.md):
      // one that does not is not a version of this publication.
      Publication(_sameScope(list..sort(newestFirst))),
  ]..sort((a, b) => newestFirst(a.latest, b.latest));
  return publications;
}

List<PublishedVersion> _sameScope(List<PublishedVersion> newestFirst) {
  final first = newestFirst.last;
  return [
    for (final v in newestFirst)
      if (v.scope == first.scope) v,
  ];
}
