import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

class WebPagesState extends Equatable {
  const WebPagesState({
    this.loaded = false,
    this.pages = const [],
    this.failed = false,
  });

  /// False until the first list is in, publications included, so the page
  /// can tell "reading" from "nothing published".
  final bool loaded;

  /// Most recently updated first.
  final List<WebPage> pages;

  /// The publications could not be read: [pages] holds deployments only.
  final bool failed;

  @override
  List<Object?> get props => [loaded, pages, failed];
}

/// Everything the signed-in owner has put on the web, for the Web pages
/// heading in the nav and the Web pages page.
///
/// Publications come from [PublicationsCubit], which reads them all in one
/// query at sign in; deployments from the local database, so they follow
/// every sync without a request of their own.
class WebPagesCubit extends Cubit<WebPagesState> {
  WebPagesCubit({
    required DriveDao driveDao,
    required PublicationsCubit publicationsCubit,
    required ProfileCubit profileCubit,
  })  : _driveDao = driveDao,
        _publications = publicationsCubit,
        super(const WebPagesState()) {
    _owner = profileCubit.stream
        .startWith(profileCubit.state)
        .map((p) => p is ProfileLoggedIn ? p.user.walletAddress : null)
        .distinct()
        .listen(_watch);
  }

  final DriveDao _driveDao;
  final PublicationsCubit _publications;
  late final StreamSubscription<String?> _owner;
  StreamSubscription<WebPagesState>? _pages;

  void _watch(String? owner) {
    _pages?.cancel();
    _pages = null;
    emit(const WebPagesState());
    if (owner == null) return;

    _pages = Rx.combineLatest3(
      _publications.stream.startWith(_publications.state),
      _driveDao.allDrives().watch(),
      _driveDao.watchDeploymentsOfOwner(owner),
      (PublicationsState publications, List<Drive> drives,
              List<FileEntry> deployments) =>
          (publications, drives, deployments),
    )
        // A sync writes in batches, and each write would compose the list
        // again: wait for a pause, and drop a composition that a newer one
        // has made stale.
        .debounceTime(const Duration(milliseconds: 200))
        .switchMap((sources) => Stream.fromFuture(
            _compose(owner, sources.$1, sources.$2, sources.$3)))
        .listen(
          emit,
          onError: (Object e) =>
              logger.w('[web pages] could not list web pages: $e'),
        );
  }

  Future<WebPagesState> _compose(
    String owner,
    PublicationsState publications,
    List<Drive> allDrives,
    List<FileEntry> deployments,
  ) async {
    final drives = {
      for (final d in allDrives)
        if (d.ownerAddress == owner && d.isPublic) d.id: d,
    };
    final all = [
      for (final p in publications.byDrive.values) ...p.publications,
    ];
    final folderIds = {
      for (final p in all)
        if (p.folderId != null) p.folderId!,
      for (final f in deployments) f.parentFolderId,
    };
    final folders = folderIds.isEmpty
        ? const <FolderEntry>[]
        : await _driveDao.foldersByIds(folderIds: folderIds.toList()).get();
    return WebPagesState(
      // Publications still being read would show as "nothing published".
      loaded: publications.status != PublicationsStatus.loading,
      failed: publications.status == PublicationsStatus.failed,
      pages: composeWebPages(
        publications: all,
        deployments: deployments,
        drives: drives,
        folders: {for (final f in folders) f.id: f},
      ),
    );
  }

  /// Reads the publications again after a failure.
  Future<void> retry() => _publications.retry();

  @override
  void emit(WebPagesState state) {
    if (isClosed) return;
    super.emit(state);
  }

  @override
  Future<void> close() async {
    await _owner.cancel();
    await _pages?.cancel();
    return super.close();
  }
}
