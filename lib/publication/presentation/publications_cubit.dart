import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';

/// A drive's publications as far as this session knows them.
class DrivePublications extends Equatable {
  const DrivePublications({this.loading = false, this.publications = const []});

  final bool loading;
  final List<Publication> publications;

  /// The publication of the whole drive ([folderId] null) or of a folder.
  /// Never a file page: a file has no folder either, and is not its drive.
  Publication? of(String? folderId) => ofScope(folderId == null
      ? const PublicationDriveScope()
      : PublicationFolderScope(folderId));

  /// The page of one file.
  Publication? ofFile(String fileId) => ofScope(PublicationFileScope(fileId));

  Publication? ofScope(PublicationScope scope) {
    for (final p in publications) {
      if (p.scope == scope) return p;
    }
    return null;
  }

  @override
  List<Object?> get props => [loading, publications];
}

/// Where the owner's publications are: [idle] before any are asked for, and
/// where they never are (off the web, inside a publication).
enum PublicationsStatus { idle, loading, loaded, failed }

class PublicationsState extends Equatable {
  const PublicationsState([
    this.byDrive = const {},
    this.status = PublicationsStatus.idle,
  ]);

  final Map<String, DrivePublications> byDrive;
  final PublicationsStatus status;

  Publication? publicationOf(String driveId, String? folderId) =>
      byDrive[driveId]?.of(folderId);

  Publication? filePageOf(String driveId, String fileId) =>
      byDrive[driveId]?.ofFile(fileId);

  @override
  List<Object?> get props => [byDrive, status];
}

/// Which of the signed-in owner's drives and folders are published to the
/// web, for the mark beside them and for "Publish to web" to open the
/// published view instead (docs/PUBLICATIONS.md, "Entry points").
///
/// One GraphQL query when a wallet signs in finds every publication it
/// made; another after this session publishes, merged with what it
/// published, since GraphQL lags.
class PublicationsCubit extends Cubit<PublicationsState> {
  PublicationsCubit({
    required PublicationRepository repository,
    required ProfileCubit profileCubit,
  })  : _repository = repository,
        _profileCubit = profileCubit,
        super(const PublicationsState()) {
    _changes = repository.changes.listen((_) {
      final owner = _owner;
      if (owner != null) _load = _loadAll(owner);
    });
    _profile = profileCubit.stream.listen((_) => _onProfile());
    _onProfile();
  }

  void _onProfile() {
    if (!kIsWeb || PublicationMode.isOn) return;
    if (_owner != null) {
      watchOwner();
    } else if (_loadedFor != null) {
      _loadedFor = null;
      _load = null;
      emit(const PublicationsState());
    }
  }

  final PublicationRepository _repository;
  final ProfileCubit _profileCubit;
  late final StreamSubscription<String> _changes;
  late final StreamSubscription<ProfileState> _profile;
  Future<void>? _load;
  String? _loadedFor;

  String? get _owner {
    final profile = _profileCubit.state;
    return profile is ProfileLoggedIn ? profile.user.walletAddress : null;
  }

  /// Whether [drive] can be published by whoever is signed in.
  bool canPublish(Drive drive) => drive.isPublic && _owns(drive);

  /// Whether a file in [drive] can have a page: the owner's, in a public or
  /// a private drive. A private file's page opens with the key in its link.
  bool canPublishFile(Drive drive) => _owns(drive);

  bool _owns(Drive drive) => _owner != null && drive.ownerAddress == _owner;

  /// Asks again after a failure.
  Future<void> retry() {
    _load = null;
    return watchOwner();
  }

  /// Starts finding the owner's publications, unless known already. One
  /// query covers every drive, so the drives list can mark them all.
  Future<void> watchOwner() {
    final owner = _owner;
    if (owner == null) return Future.value();
    if (_loadedFor != owner) {
      _loadedFor = owner;
      _load = null;
      emit(const PublicationsState());
    }
    return _load ??= _loadAll(owner);
  }

  /// [drive]'s publications, found if they are not known yet; null when
  /// GraphQL could not say, twice. Never "none" on a failure: that would
  /// start a second publication of something already published.
  Future<DrivePublications?> publicationsOf(Drive drive) async {
    // A private drive can have file pages, so it is looked up like any other
    // the owner holds; "none" for a drive that is not theirs.
    if (!_owns(drive)) return const DrivePublications();
    await watchOwner();
    if (_failed) {
      _load = null;
      await watchOwner();
      if (_failed) return null;
    }
    return state.byDrive[drive.id] ?? const DrivePublications();
  }

  bool _failed = false;

  Future<void> _loadAll(String owner) async {
    // A reload after a publish keeps what is shown; only a first read, or one
    // after a failure, says it is reading.
    if (state.status != PublicationsStatus.loaded) {
      emit(PublicationsState(state.byDrive, PublicationsStatus.loading));
    }
    try {
      final byDrive = await _repository.publicationsOfOwner(owner);
      _failed = false;
      if (isClosed || _loadedFor != owner) return;
      emit(PublicationsState({
        for (final MapEntry(:key, :value) in byDrive.entries)
          key: DrivePublications(publications: value),
      }, PublicationsStatus.loaded));
    } on PublicationReadException catch (e) {
      logger.w('[publication] could not list publications: $e');
      _failed = true;
      _load = null;
      if (isClosed || _loadedFor != owner) return;
      emit(PublicationsState(state.byDrive, PublicationsStatus.failed));
    }
  }

  @override
  Future<void> close() {
    _changes.cancel();
    _profile.cancel();
    return super.close();
  }
}
