part of 'shared_file_cubit.dart';

/// How the claims a v2 link makes about a file compare with the file's own
/// record on chain.
///
/// A v2 link asserts its own contents - the data transaction it points at, the
/// name, the size, the type - so that the page can paint without waiting for
/// GraphQL. That assertion is an optimization, never a source of truth: a link
/// can be stale, truncated, or crafted. The recipient therefore gets the fast
/// paint *and*, moments later, a verdict on whether the link was telling the
/// truth.
///
/// See `docs/FILE_SHARING_REDESIGN_PLAN.md` §2, the `READY` row.
enum LinkVerification {
  /// The check is still running. Nothing is known yet, and nothing is claimed.
  pending,

  /// The file's metadata transaction agrees with every field the link
  /// asserted.
  verified,

  /// The metadata transaction disagrees with the link. The on-chain values are
  /// what the page shows and downloads from that point on; the badge tells the
  /// recipient that the link's own description of the file was wrong.
  mismatch,

  /// There is nothing to check the link against: it carried no `mtx`, or the
  /// metadata could not be fetched. Renders as "unverified", never as an
  /// error - most links in the wild are simply v1 links.
  unavailable,
}

/// Whether the file's revision history has been loaded.
///
/// The history costs one metadata fetch per revision, which is the dominant
/// cost of the first paint today, so it is never fetched during resolution.
/// The UI asks for it with [SharedFileCubit.loadActivity] when the activity
/// view is opened for the first time.
enum SharedFileActivityStatus {
  notLoaded,
  loading,
  loaded,
  failed,
}

@immutable
abstract class SharedFileState extends Equatable {
  const SharedFileState();

  @override
  List<Object?> get props => [];
}

class SharedFileLoadInProgress extends SharedFileState {
  /// What the link itself said about the file, if anything.
  ///
  /// Carried through the loading state so that a v2 link can paint a skeleton
  /// with the real name and size while resolution is still running. `null` for
  /// a v1 link, which knows nothing until GraphQL answers.
  final SharedFileLinkPayload? payload;

  const SharedFileLoadInProgress({this.payload});

  @override
  List<Object?> get props => [payload];
}

/// [SharedFileIsPrivate] indicates that the shared file is encrypted and that a
/// file key is needed before anything about it can be shown.
///
/// This state is terminal until the recipient supplies a key. No file key can
/// be recovered from the network: it is derived from the owner's wallet and
/// drive key and never exists on chain, so nothing here is ever retried in the
/// hope of finding one.
class SharedFileIsPrivate extends SharedFileState {
  final SharedFileLinkPayload? payload;

  const SharedFileIsPrivate({this.payload});

  @override
  List<Object?> get props => [payload];
}

/// [SharedFileLoadSuccess] indicates that the shared file being viewed has been
/// loaded successfully.
class SharedFileLoadSuccess extends SharedFileState {
  /// The revision(s) describing the file being shown.
  ///
  /// `first` is always the target: the revision whose bytes the download and
  /// preview act on. It never changes because the history loaded, and it never
  /// changes because a newer revision exists - both would swap the file out
  /// from under the recipient (`docs/FILE_SHARING_REDESIGN_PLAN.md`, decision
  /// 1). It changes only when the file's own metadata proves the link wrong,
  /// which is the one case where the link is not worth honoring.
  final List<FileRevision> fileRevisions;

  final SecretKey? fileKey;
  final LicenseState? latestLicense;
  final String? ownerAddress;

  /// What the link asserted, or `null` for a v1 link.
  ///
  /// Kept on the state so the UI can show what the link claimed even after the
  /// on-chain record has overridden it.
  final SharedFileLinkPayload? payload;

  /// The verdict of the background check against the file's metadata
  /// transaction. Never blocks this state from being emitted.
  final LinkVerification verification;

  /// Whether a revision newer than [fileRevisions] `.first` exists.
  ///
  /// The page offers it; it never swaps to it on its own.
  final bool newerVersionAvailable;

  /// Whether the link was pinned to the revision it was made from.
  ///
  /// Only changes what the UI offers when [newerVersionAvailable] is set
  /// ("View latest" rather than "Get latest"); the freshness check runs either
  /// way.
  final bool isPinned;

  /// Whether [fileRevisions] came from the file's own metadata rather than
  /// from the link.
  ///
  /// `false` while the header is painted from a v2 payload alone. Fields the
  /// link did not carry are then placeholders - an empty name, a zero size, an
  /// epoch date - and the UI shows its generic copy for them until the
  /// background metadata resolution fills them in.
  final bool detailsAreResolved;

  /// The file's revision history, once [SharedFileCubit.loadActivity] has been
  /// asked for it. Empty until then.
  final List<FileRevision> activityRevisions;

  final SharedFileActivityStatus activityStatus;

  /// The revision the link itself pointed at, once the recipient has asked to
  /// see a different one.
  ///
  /// `null` until [SharedFileCubit.showLatestRevision] has been called, and set
  /// from then on - including after
  /// [SharedFileCubit.showSharedRevision] has put it back - so that the page
  /// can always say which revision the link named and can always go back to it.
  final FileRevision? linkRevision;

  /// Whether the page is showing the file's newest revision because the
  /// recipient asked for it.
  ///
  /// Never set by the freshness check: the page offers a newer revision and
  /// only ever adopts one when the recipient presses for it
  /// (`docs/FILE_SHARING_REDESIGN_PLAN.md`, decision 1).
  final bool showsLatestRevision;

  const SharedFileLoadSuccess({
    required this.fileRevisions,
    this.fileKey,
    this.latestLicense,
    this.ownerAddress,
    this.payload,
    this.verification = LinkVerification.pending,
    this.newerVersionAvailable = false,
    this.isPinned = false,
    this.detailsAreResolved = true,
    this.activityRevisions = const [],
    this.activityStatus = SharedFileActivityStatus.notLoaded,
    this.linkRevision,
    this.showsLatestRevision = false,
  });

  /// The revision the page acts on. See [fileRevisions].
  FileRevision get revision => fileRevisions.first;

  /// The revision the link named, whatever the page is showing right now.
  ///
  /// What the version history marks as the shared version, so that the marker
  /// keeps pointing at the revision that was actually sent even after the
  /// recipient has asked to see the newest one.
  FileRevision get sharedRevision => linkRevision ?? revision;

  SharedFileLoadSuccess copyWith({
    List<FileRevision>? fileRevisions,
    SecretKey? fileKey,
    LicenseState? latestLicense,
    String? ownerAddress,
    SharedFileLinkPayload? payload,
    LinkVerification? verification,
    bool? newerVersionAvailable,
    bool? isPinned,
    bool? detailsAreResolved,
    List<FileRevision>? activityRevisions,
    SharedFileActivityStatus? activityStatus,
    FileRevision? linkRevision,
    bool? showsLatestRevision,
  }) =>
      SharedFileLoadSuccess(
        fileRevisions: fileRevisions ?? this.fileRevisions,
        fileKey: fileKey ?? this.fileKey,
        latestLicense: latestLicense ?? this.latestLicense,
        ownerAddress: ownerAddress ?? this.ownerAddress,
        payload: payload ?? this.payload,
        verification: verification ?? this.verification,
        newerVersionAvailable:
            newerVersionAvailable ?? this.newerVersionAvailable,
        isPinned: isPinned ?? this.isPinned,
        detailsAreResolved: detailsAreResolved ?? this.detailsAreResolved,
        activityRevisions: activityRevisions ?? this.activityRevisions,
        activityStatus: activityStatus ?? this.activityStatus,
        linkRevision: linkRevision ?? this.linkRevision,
        showsLatestRevision: showsLatestRevision ?? this.showsLatestRevision,
      );

  @override
  List<Object?> get props => [
        fileRevisions,
        fileKey,
        // The license resolves after the page is painted on the fast path, so
        // it has to count towards equality or that emit would be dropped as a
        // no-op.
        latestLicense,
        ownerAddress,
        payload,
        verification,
        newerVersionAvailable,
        isPinned,
        detailsAreResolved,
        activityRevisions,
        activityStatus,
        linkRevision,
        showsLatestRevision,
      ];
}

/// [SharedFileKeyInvalid] indicates that a file key was provided - either typed
/// by the user or read from the link - but that it could not decrypt the file's
/// metadata.
///
/// The file itself is known to exist, so this must never be reported as a
/// missing file. The key entry gate stays on screen with an inline error so
/// that another key can be tried.
class SharedFileKeyInvalid extends SharedFileState {
  /// Whether the key never made it out of the link intact, as opposed to a key
  /// that was decoded and then failed to decrypt the file.
  ///
  /// A damaged key means the link itself arrived mangled - truncated by a mail
  /// client, cut short by a chat app - so the recipient is told to ask for the
  /// link again rather than to re-check a key they never really had.
  final bool linkKeyIsDamaged;

  /// What the link asserted, so that the locked card can still show the file's
  /// name and size when the sharer embedded them.
  final SharedFileLinkPayload? payload;

  const SharedFileKeyInvalid({
    this.linkKeyIsDamaged = false,
    this.payload,
  });

  @override
  List<Object?> get props => [linkKeyIsDamaged, payload];
}

/// [SharedFileLinkDamaged] indicates that the link did not survive the trip
/// intact enough to name a file at all.
///
/// This is the `ERROR_LINK` state of `docs/FILE_SHARING_REDESIGN_PLAN.md` §2,
/// and it is deliberately narrow. Every *field* of a v2 link is dropped rather
/// than fatal when it arrives malformed, and a damaged key is answered by the
/// key gate ([SharedFileKeyInvalid] with `linkKeyIsDamaged`), so the only thing
/// left that no amount of network access can recover from is a link with no
/// usable file id.
///
/// The route parser can produce exactly that: `Uri.pathSegments` keeps empty
/// segments, so `/file//view` parses as a shared file route whose file id is
/// the empty string (`AppRoutePath.sharedFile(sharedFileId: '')`), and
/// `AppRouterDelegate.isViewingSharedFile` is `sharedFileId != null`, so the
/// page is built for it. Anything else malformed enough to fail
/// `Uri.parse` degrades to `AppRoutePath.unknown()` and never reaches here.
///
/// Terminal: there is nothing to retry, because only the sender can fix it.
class SharedFileLinkDamaged extends SharedFileState {
  const SharedFileLinkDamaged();
}

/// [SharedFileNotFound] indicates that no file with the shared file id could be
/// found on the network.
class SharedFileNotFound extends SharedFileState {
  /// How many automatic retries have been spent so far.
  ///
  /// Drives the "Retrying in {n}s…" copy, and lets the card show a plain retry
  /// button once the budget is gone.
  final int retryAttempt;

  /// Whether the file is expected to exist and is probably still propagating.
  ///
  /// Set when the link asserted a data transaction: something was uploaded, so
  /// an all-gateway miss is far more likely to be a recently uploaded file that
  /// has not spread yet than a file id that never existed. A v1 link whose
  /// owner probe came back empty is the other case, and keeps saying that the
  /// file does not exist.
  final bool mayStillBePropagating;

  const SharedFileNotFound({
    this.retryAttempt = 0,
    this.mayStillBePropagating = false,
  });

  @override
  List<Object?> get props => [retryAttempt, mayStillBePropagating];
}

/// [SharedFileLoadFailure] indicates that the shared file could not be loaded
/// because of an unexpected failure, typically a network or gateway error.
///
/// The load can be run again with [SharedFileCubit.retry].
class SharedFileLoadFailure extends SharedFileState {}
