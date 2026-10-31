import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/utils/mime_lookup.dart';
import 'package:equatable/equatable.dart';

enum WebPageKind {
  /// A published drive or folder (docs/PUBLICATIONS.md).
  publication,

  /// One file's page: its share page, published (docs/PUBLICATIONS.md, "File
  /// pages"). A private file's page opens with the key in its link.
  filePage,

  /// A manifest file, which users know as a deployment.
  deployment,
}

/// Something the signed-in user has put on the web: a row of the Web pages
/// page and of its nav heading.
class WebPage extends Equatable {
  const WebPage({
    required this.kind,
    required this.id,
    required this.title,
    required this.driveId,
    required this.driveName,
    required this.folderName,
    required this.openFolderId,
    required this.dataTxId,
    required this.updatedAt,
    this.publication,
    this.isPrivate = false,
    this.contentType,
  });

  final WebPageKind kind;

  /// The publication ID, or the deployment's file ID.
  final String id;

  /// The folder or drive it publishes, or the deployment's file name.
  final String title;

  final String driveId;
  final String driveName;

  /// The folder it publishes or sits in; null at the drive's root, where
  /// the drive is all there is to say.
  final String? folderName;

  /// Where Open folder goes in the drive explorer.
  final String openFolderId;

  /// What its link opens: the publication's latest version, or the
  /// deployment's data.
  final String dataTxId;

  final DateTime updatedAt;

  /// Set for a publication or a file page, for Update page.
  final Publication? publication;

  /// A private file's page: its link needs the file's key to open.
  final bool isPrivate;

  /// A file page's file type, for its icon: the file's content type, or the
  /// one its name implies when an older upload carries none.
  final String? contentType;

  /// A publication of a whole drive rather than one of its folders.
  bool get isDrivePublication =>
      kind == WebPageKind.publication && folderName == null;

  bool get isDeployment => kind == WebPageKind.deployment;
  bool get isFilePage => kind == WebPageKind.filePage;

  @override
  List<Object?> get props => [
        kind,
        id,
        title,
        driveId,
        driveName,
        folderName,
        openFolderId,
        dataTxId,
        updatedAt,
        publication,
        isPrivate,
        contentType,
      ];
}

/// The Web pages list: [publications] and [deployments] in the owner's
/// public [drives], and file pages in any of their [drives], most recently
/// updated first. [files] are the files file pages show.
///
/// A publication whose drive or folder is not on this device yet is left
/// out: there is no name to show for it and nowhere to open. It appears once
/// the drive syncs.
List<WebPage> composeWebPages({
  required Iterable<Publication> publications,
  required Iterable<FileEntry> deployments,
  required Map<String, Drive> drives,
  required Map<String, FolderEntry> folders,
  Map<String, FileEntry> files = const {},
}) {
  final pages = <WebPage>[];

  for (final publication in publications) {
    final latest = publication.latest;
    final drive = drives[latest.driveId];
    if (drive == null) continue;
    if (latest.scope case PublicationFileScope(:final fileId)) {
      final file = files[fileId];
      // Not on this device yet, or hidden: left out, as a hidden deployment
      // is.
      if (file == null || file.isHidden) continue;
      final inRoot = file.parentFolderId == drive.rootFolderId;
      pages.add(WebPage(
        kind: WebPageKind.filePage,
        id: publication.id,
        title: file.name,
        driveId: drive.id,
        driveName: drive.name,
        folderName: inRoot ? null : folders[file.parentFolderId]?.name,
        openFolderId: file.parentFolderId,
        dataTxId: latest.txId,
        updatedAt: latest.publishedAt,
        publication: publication,
        isPrivate: drive.isPrivate,
        contentType: switch (file.dataContentType) {
          final type? when type.isNotEmpty => type,
          _ => lookupMimeType(file.name),
        },
      ));
      continue;
    }
    if (!drive.isPublic) continue;
    final folderId = latest.scope.folderIdOrNull;
    final isDrive = folderId == null || folderId == drive.rootFolderId;
    final folder = isDrive ? null : folders[folderId];
    if (!isDrive && folder == null) continue;
    pages.add(WebPage(
      kind: WebPageKind.publication,
      id: publication.id,
      title: folder?.name ?? drive.name,
      driveId: drive.id,
      driveName: drive.name,
      folderName: folder?.name,
      openFolderId: folder?.id ?? drive.rootFolderId,
      dataTxId: latest.txId,
      updatedAt: latest.publishedAt,
      publication: publication,
    ));
  }

  for (final file in deployments) {
    final drive = drives[file.driveId];
    if (drive == null || !drive.isPublic || file.isHidden) continue;
    final inRoot = file.parentFolderId == drive.rootFolderId;
    pages.add(WebPage(
      kind: WebPageKind.deployment,
      id: file.id,
      title: file.name,
      driveId: drive.id,
      driveName: drive.name,
      folderName: inRoot ? null : folders[file.parentFolderId]?.name,
      openFolderId: file.parentFolderId,
      dataTxId: file.dataTxId,
      updatedAt: file.lastUpdated,
    ));
  }

  pages.sort((a, b) {
    final byDate = b.updatedAt.compareTo(a.updatedAt);
    return byDate != 0
        ? byDate
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return pages;
}

/// Where people find a web page.
class WebPageLink extends Equatable {
  const WebPageLink({required this.url, this.arnsRecord});

  final String url;

  /// The name it is found by, when one of the user's names points at it.
  final ArNSNameRecord? arnsRecord;

  /// The link as it is read: `maya.ar.io`, or the gateway's host and the
  /// ends of the transaction ID (`ardrive.net/pubStu...xQ0c`). A whole ID
  /// wrapped over two lines and told the reader nothing more.
  String get label {
    final record = arnsRecord;
    if (record != null) return arnsHostFor(record.literalName);
    final uri = Uri.parse(url);
    final path = uri.pathSegments.where((s) => s.isNotEmpty).join('/');
    final short = path.length > 12
        ? '${path.substring(0, 6)}...${path.substring(path.length - 4)}'
        : path;
    return '${uri.host}/$short';
  }

  @override
  List<Object?> get props => [url, arnsRecord];
}

/// [page]'s link: a name of the user's that points at it, else the link the
/// app gives it everywhere else - the published view's for a publication,
/// the data gateway's for a deployment.
WebPageLink webPageLinkFor(
  WebPage page, {
  required List<ArNSManagedName> names,
  required String publicationGatewayUrl,
  required String dataGatewayUrl,
}) {
  final record = webPageRecord(page, names);
  if (record != null) {
    return WebPageLink(
      url: arnsUrlFor(record.literalName),
      arnsRecord: record,
    );
  }
  return WebPageLink(
    url: page.isDeployment
        ? '$dataGatewayUrl/${page.dataTxId}'
        : '$publicationGatewayUrl/${page.dataTxId}/',
  );
}

/// The first of [names]' records that points at [page]'s current version.
ArNSNameRecord? webPageRecord(WebPage page, List<ArNSManagedName> names) {
  for (final name in names) {
    for (final record in name.records) {
      final target = record.target;
      final pointsHere = record.transactionId == page.dataTxId ||
          switch (target) {
            ArNSPublicationItem(:final publicationId, :final isLatestVersion) =>
              !page.isDeployment && publicationId == page.id && isLatestVersion,
            ArNSFileItem(:final fileId, :final isLatestVersion) =>
              page.isDeployment && fileId == page.id && isLatestVersion,
            null => false,
          };
      if (pointsHere) return record;
    }
  }
  return null;
}
