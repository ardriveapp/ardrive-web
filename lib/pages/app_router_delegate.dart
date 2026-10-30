import 'dart:async';

import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/arns/presentation/resume/arns_resume_scope.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/web_pages/presentation/web_pages_page.dart';
import 'package:ardrive/drive_explorer/dock/ardrive_dock.dart';
import 'package:ardrive/drive_explorer/multi_thumbnail_creation/multi_thumbnail_creation_modal.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/publication/data/publication_owner_lookup.dart';
import 'package:ardrive/publication/data/publication_source.dart';
import 'package:ardrive/publication/domain/file_page.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/publication/presentation/publication_loader_page.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_page.dart';
import 'package:ardrive/search/search_scope.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/upload_entry/domain/upload_request.dart';
import 'package:ardrive/upload_entry/presentation/start_upload.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  bool signingIn = false;

  bool gettingStarted = false;

  /// Whether the drives list is what is on screen.
  ///
  /// Where a login lands when it has no link to honour. It is deliberately not
  /// derived from `driveId == null`: a drive is selected underneath the list -
  /// the sidebar has to show something - so only this says which of the two
  /// the user is actually looking at.
  bool showingDrivesList = false;

  /// Whether the Names page is what is on screen (docs/NAMES.md). Like the
  /// drives list, a drive stays selected under it for the sidebar.
  bool showingNames = false;

  /// With [showingNames], the one name whose page is on screen; null for
  /// every name.
  String? shownName;

  /// Whether the Web pages page is what is on screen: what the user has
  /// published. Like the Names page, a drive stays selected under it.
  bool showingWebPages = false;

  /// The scope the drives list opens on, from a drive heading in the nav or
  /// the Web pages page's way to public drives.
  DriveScope drivesListScope = DriveScope.all;

  String? driveId;
  String? driveName;
  String? driveFolderId;

  /// The drive a folder link named, held until that drive is the selected one.
  ///
  /// A folder link opened by someone who does not have the drive yet goes
  /// through the attach flow, which ends by clearing [driveId] so the prompt
  /// cannot re-fire. The drive is then selected fresh, [driveFolderId] reads as
  /// belonging to a different drive, and the folder the link named is dropped -
  /// so every recipient who was not already in the drive landed at its root,
  /// which made a folder link a drive link with extra characters.
  ///
  /// One shot: cleared as soon as that drive is selected, so ordinary
  /// navigation away from the drive still discards the folder as it always has.
  String? _pendingFolderDriveId;

  /// The folder that link named, held with the drive it belongs to.
  ///
  /// Kept alongside [_pendingFolderDriveId] rather than read off
  /// [driveFolderId] when the drive arrives: between the link opening and that
  /// drive being selected the recipient may have been somewhere else entirely,
  /// and [driveFolderId] would by then hold a folder from whatever drive they
  /// were last in. Restoring *this* is the difference between opening the
  /// folder the link named and opening another drive's folder under this
  /// drive's name.
  String? _pendingFolderId;

  /// A folder asked for by a search result, and the file to pick out of it.
  ///
  /// Deliberately *not* [_pendingFolderId]. That one is a folder deep link, and
  /// a link is not an instruction to resume: tapping a drive on the list after
  /// arriving through `/drives/X/folders/Y` opens X at its root, which
  /// `drives_list_routing_test` pins. A search result is the opposite - the
  /// reader picked a folder out of a list of them - so it has to survive the
  /// same call that discards the link.
  String? _requestedFolderDriveId;
  String? _requestedFolderId;
  String? _requestedItemId;

  /// The selection waiting for the cubit that is about to be built, and the
  /// drive it belongs to.
  ///
  /// Keyed by drive because [_driveDetailCubit] builds twice over: once for the
  /// drives list, against the root path, and once for the explorer against the
  /// chosen drive. Unkeyed, the list's cubit would swallow a selection meant for
  /// the explorer and the file would never be highlighted.
  String? _selectedItemForFolder;
  String? _selectedItemForFolderDriveId;

  /// The drive whose info panel should open once that drive has loaded.
  ///
  /// The drives list can only ask; it cannot open the panel itself. The panel
  /// is `DriveDetailCubit.selectDataItem`, which begins `this.state as
  /// DriveDetailLoadSuccess`, and the cubit the list page provides is built
  /// against no drive at all - and is a different instance from the explorer's
  /// in any case. So the request travels the way a folder link's does: held
  /// here, honoured by the explorer's own cubit when it reports the drive
  /// loaded, and cleared the moment it is.
  ///
  /// One shot, for the same reason [_pendingFolderId] is: navigating back into
  /// the drive later must not reopen a panel nobody asked for again.
  String? _pendingInfoDriveId;

  /// The drive and folder the address bar last asked for, until the explorer
  /// takes it.
  ///
  /// The explorer read the route once, when it was built. A link pasted into
  /// a tab that already had it open, or a step back or forward through its
  /// history, changed the address bar and nothing else: the next folder the
  /// explorer drew put the old address back, and a link to another drive left
  /// the sidebar on the old one. See [followRouteLink].
  RouteLink? _routeLink;

  /// The drive a visitor just opened from the sign-in screen, whose sync has
  /// to start the moment there is a `SyncCubit` to start it on.
  ///
  /// That cubit lives inside the explorer's provider tree, which does not
  /// exist on the sign-in screen, so the dialog that wrote the drive cannot
  /// start the sync itself. The explorer's cubit factory does, once, and the
  /// detail cubit then shows "Opening..." instead of the unsynced card.
  String? _syncOnOpenDriveId;

  /// The private drive a visitor has already been asked a key for, so the
  /// prompt opens once per drive rather than on every state the explorer
  /// emits while the drive is open. A new route asks again.
  String? _keyPromptedForDriveId;

  /// The drive [sharedDriveKey] came with. A key is only ever offered to the
  /// drive its link named: selecting another drive drops it, so it can't be
  /// tried on, stored for, or shown in the address bar of a drive it doesn't
  /// belong to.
  String? _sharedDriveKeyDriveId;

  /// The drive to sync as the explorer builds, for tests.
  @visibleForTesting
  String? get syncOnOpenDriveId => _syncOnOpenDriveId;

  /// The standing request, for tests. The explorer clears it as it honours it.
  @visibleForTesting
  String? get pendingInfoDriveId => _pendingInfoDriveId;

  /// The upload somebody asked for before its drive was open.
  ///
  /// Held and honoured the way [_pendingInfoDriveId] is, for the same reason:
  /// an upload can only start from inside a loaded drive, because
  /// `promptToUpload` reads the explorer's own cubit. When the drive reports
  /// in, the explorer opens the upload dialog if it is loaded, or starts its
  /// sync if nothing has read it, and clears this either way.
  UploadRequest? _pendingUpload;

  /// Ends a waiting upload that its drive never came to.
  Timer? _pendingUploadExpiry;

  /// How long an upload waits for its drive to open.
  ///
  /// Opening takes a second or two. Anything longer is a drive the explorer
  /// is holding back for some other reason, and an upload dialog that turned
  /// up afterwards would land on whatever the reader had moved on to - or,
  /// if they came back to that drive later, on a visit that had nothing to do
  /// with it.
  static const uploadWaitLimit = Duration(seconds: 10);

  /// The standing upload request, for tests.
  @visibleForTesting
  UploadRequest? get pendingUpload => _pendingUpload;

  /// Reconciles the folder in view with the drive that has just been selected.
  ///
  /// Selecting a different drive discards the folder, which is what ordinary
  /// navigation wants - a folder from the drive you just left is stale. The one
  /// exception is the drive a folder link named: it becomes selected *because*
  /// of that link, so its folder is the whole point rather than a leftover.
  ///
  /// Extracted from the listener that calls it so it can be tested without
  /// standing up the whole app shell.
  @visibleForTesting
  void onDriveSelected(String? selectedDriveId) {
    final selectedDriveChanged = driveId != selectedDriveId;

    if (selectedDriveChanged && selectedDriveId != _sharedDriveKeyDriveId) {
      sharedDriveKey = null;
      sharedRawDriveKey = null;
      _sharedDriveKeyDriveId = null;
    }

    final isTheLinkedDrive = _pendingFolderDriveId != null &&
        _pendingFolderDriveId == selectedDriveId;

    if (isTheLinkedDrive) {
      // The folder the link named, not the one in view - see [_pendingFolderId].
      driveFolderId = _pendingFolderId;

      // One shot. Released as soon as it is honored, so navigating away from
      // the drive and back lands at its root rather than jumping to the old
      // folder.
      _pendingFolderDriveId = null;
      _pendingFolderId = null;
    } else if (selectedDriveChanged) {
      driveFolderId = null;
    }

    driveId = selectedDriveId;
  }

  DriveKey? sharedDriveKey;
  String? sharedRawDriveKey;

  String? sharedFileId;
  SecretKey? sharedFileKey;
  String? sharedRawFileKey;
  bool sharedFileKeyIsDamaged = false;

  /// The v2 payload the shared file link embedded, or `null` for a v1 link.
  SharedFileLinkPayload? sharedFileLinkPayload;

  /// The transaction `/view/{txId}` was asked for, and its optional hints.
  String? rawTransactionId;
  String? rawTransactionName;
  String? rawTransactionContentType;

  /// The publication this page opened (`PublicationMode`), once it is in the
  /// database. Until then the page shows the publication's loading screens.
  PublicationConfig? publication;

  /// The place in the publication the address bar asked for, until the publication is
  /// there to look it up in. See [_followPublicationLink].
  String? _publicationFolderRequest;
  String? _publicationFileRequest;

  /// Answers whether a folder is inside the publication; set with [publication].
  Future<bool> Function(String folderId)? _isInPublicationScope;

  bool canAnonymouslyShowDriveDetail(ProfileState profileState) =>
      PublicationMode.isOn
          // A publication has no account and needs none: the explorer opens
          // once the publication is imported, whatever the profile is doing.
          ? publication != null
          : profileState is ProfileUnavailable && tryingToViewDrive;

  /// Whether the drives list is somewhere this viewer can actually go.
  ///
  /// The explorer renders for a logged-out viewer as well - that is what
  /// [canAnonymouslyShowDriveDetail] is for - but the drives list does not,
  /// and the shell around the explorer offered the way there regardless. A
  /// recipient opening a share link with no profile got a nav entry and a
  /// breadcrumb root that flipped a flag nothing read: the screen never
  /// changed, the address bar started claiming `/drives`, the entry lit up as
  /// though it were the page in view, and every later tap was a hard no-op
  /// because [showDrivesList] returns early on the flag it just set.
  ///
  /// Read by the branch that renders the list and by every control that offers
  /// it, so the two cannot disagree.
  static bool canShowDrivesList(ProfileState profileState) =>
      profileState is ProfileLoggedIn;

  /// Whether the sign-in page shows while the app is still checking for an
  /// account on this device.
  ///
  /// Every start without a link ends on the sign-in page, whatever the check
  /// finds: Welcome back for an account, the landing for none. So the page
  /// comes up at once, its panel drawn from [ProfileCubit.presence] and
  /// usable once the check is in, rather than a blank page for as long as
  /// the database takes to open. A link (a drive, a shared file, a raw
  /// transaction) still waits: for a visitor it ends somewhere else. Built
  /// under [signingIn]'s key, so the page and its state carry over when the
  /// check ends.
  @visibleForTesting
  bool signsInWhileChecking(ProfileState profileState) =>
      _routeKnown &&
      profileState is ProfileCheckingAvailability &&
      !PublicationMode.isOn &&
      !gettingStarted &&
      !hasARouteToHonour;

  /// Whether the address the app was opened at has been read. The first
  /// frame can come before it is ([setNewRoutePath] is asynchronous), and
  /// until then a link looks like no link: the sign-in page went up and came
  /// down again on a reload of a drive.
  bool _routeKnown = false;

  /// The profile the app is built with, for [setNewRoutePath] to read the
  /// state when the address changes. Null until the first build.
  @visibleForTesting
  ProfileCubit? profileCubit;

  bool get tryingToViewDrive => driveId != null;
  bool get tryingToViewSharedPrivateDrive => sharedDriveKey != null;
  bool get isViewingSharedFile => sharedFileId != null;
  bool get isViewingRawTransaction => rawTransactionId != null;

  /// Whether the session is already pointed at something in particular.
  ///
  /// The one question the landing decision turns on. A link - a drive, a
  /// folder inside one, a shared file, a raw transaction - has already put its
  /// target here by the time a login completes, and every one of those links
  /// is permanent public API. So the drives list is where a login goes only
  /// when the answer is no.
  @visibleForTesting
  bool get hasARouteToHonour =>
      tryingToViewDrive || isViewingSharedFile || isViewingRawTransaction;

  @override
  AppRoutePath get currentConfiguration =>
      PublicationMode.isOn ? _publicationConfiguration : _appConfiguration;

  /// Where a publication is: its root, or the folder in view. While it is
  /// still loading, the link it was opened at: reporting the root then put
  /// `#/` in the address bar over a deep link, and left it in the history,
  /// so Back went to the root rather than where the visitor came from.
  AppRoutePath get _publicationConfiguration {
    // A private file page's key, from its link, is reported back as it came
    // so the first report does not drop it and a reload still opens the page.
    final keepKey = AppRoutePath(
      sharedFileKey: sharedFileKey,
      sharedRawFileKey: sharedRawFileKey,
      sharedFileKeyIsDamaged: sharedFileKeyIsDamaged,
    );
    if (publication == null) {
      if (sharedRawFileKey != null && _publicationFolderRequest == null) {
        return keepKey;
      }
      return AppRoutePath.publication(
        folderId: _publicationFolderRequest,
        fileId: _publicationFileRequest,
      );
    }
    if (publication?.scope is PublicationFileScope) return keepKey;
    final folderId = driveFolderId;
    if (folderId == null || folderId == publication?.scopeRootFolderId) {
      return AppRoutePath.publication();
    }
    return AppRoutePath.publication(folderId: folderId);
  }

  AppRoutePath get _appConfiguration => AppRoutePath(
        signingIn: signingIn,
        getStarted: gettingStarted,
        drivesList: showingDrivesList,
        names: showingNames,
        arnsName: showingNames ? shownName : null,
        webPages: showingWebPages,
        driveId: driveId,
        driveName: driveName,
        sharedDriveKey: sharedDriveKey,
        sharedRawDriveKey: sharedRawDriveKey,
        driveFolderId: driveFolderId,
        sharedFileId: sharedFileId,
        sharedFileKey: sharedFileKey,
        sharedRawFileKey: sharedRawFileKey,
        sharedFileKeyIsDamaged: sharedFileKeyIsDamaged,
        sharedFileLinkPayload: sharedFileLinkPayload,
        rawTransactionId: rawTransactionId,
        rawTransactionName: rawTransactionName,
        rawTransactionContentType: rawTransactionContentType,
      );

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  AppRouterDelegate() : navigatorKey = GlobalKey<NavigatorState>();

  @override
  // ignore: avoid_renaming_method_parameters
  Widget build(BuildContext navigatorContext) {
    return ArDriveAppWithDevTools(
      widget: PublicationMode.isOn ? _publicationLoader(child: _app()) : _app(),
    );
  }

  /// Opens a publication's publication, and hands it to the router once it is in
  /// the database (docs/PUBLICATIONS.md, "How a page opens").
  Widget _publicationLoader({required Widget child}) {
    return BlocProvider(
      create: (context) {
        // The gateway it detected, which the host rule allows.
        final lookup = PublicationOwnerLookup(
          gateway: Uri.parse(context
              .read<ConfigService>()
              .config
              .arweaveGatewayForDataRequest
              .url),
        );
        return PublicationLoaderCubit(
          source: PublicationSource(pageUri: Uri.base),
          settingsPath: PublicationMode.settingsPath!,
          driveDao: context.read<DriveDao>(),
          importer: DriveStateImporter(context.read<DriveDao>()),
          ownerOf: lookup.ownerOf,
          factsOf: lookup.factsOf,
        )..load();
      },
      child: BlocListener<PublicationLoaderCubit, PublicationLoaderState>(
        listener: (context, state) {
          if (state is PublicationReady) {
            openPublication(state.config, context.read<DriveDao>());
          }
        },
        child: child,
      ),
    );
  }

  /// Puts the imported publication in view: its drive, at the scope's root, or
  /// the folder a link named if that folder is inside the publication.
  @visibleForTesting
  Future<void> openPublication(
      PublicationConfig config, DriveDao driveDao) async {
    publication = config;
    // A file page is its file's share page: the router's shared file branch
    // shows it, pinned to the version that was published, with the key the
    // link carried.
    if (config.scope case PublicationFileScope(:final fileId)) {
      sharedFileId = fileId;
      sharedFileLinkPayload = filePagePayload(config);
      notifyListeners();
      return;
    }
    _isInPublicationScope = (folderId) => isInPublicationScope(
          driveDao: driveDao,
          config: config,
          folderId: folderId,
        );
    driveId = config.driveId;
    driveFolderId = config.scopeRootFolderId;
    await _followPublicationLink();
  }

  /// Opens the folder [_publicationFolderRequest] named, and picks out the file,
  /// when that folder is inside the publication; otherwise the publication's root.
  /// A link to anywhere else in the drive lands on the root, never on the
  /// folder it named.
  Future<void> _followPublicationLink() async {
    final config = publication!;
    final folderId = _publicationFolderRequest;
    final fileId = _publicationFileRequest;
    _publicationFolderRequest = null;
    _publicationFileRequest = null;

    final inScope =
        folderId != null && await _isInPublicationScope!.call(folderId);
    final target = inScope ? folderId : config.scopeRootFolderId;

    driveFolderId = target;
    _selectedItemForFolder = inScope ? fileId : null;
    _selectedItemForFolderDriveId = config.driveId;
    _routeLink = RouteLink(driveId: config.driveId, folderId: target);
    notifyListeners();
  }

  Widget _app() {
    return ArDriveDock(
      child: MultiThumbnailCreationWrapper(
        child: BlocConsumer<ThemeSwitcherBloc, ThemeSwitcherState>(
          listener: (context, state) {
            if (state is ThemeSwitcherDarkTheme) {
              ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.dark);
            } else if (state is ThemeSwitcherLightTheme) {
              ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.light);
            }
          },
          builder: (context, _) => BlocConsumer<ProfileCubit, ProfileState>(
            listener: (context, state) {
              // Signing in and out, and where they land, are not things a
              // publication does.
              if (PublicationMode.isOn) return;

              // Clear state to prevent the last drive from being attached on new
              // login.
              if (state is ProfileLoggingOut) {
                logger.d('Logging out. Clearing state.');

                clearState();
              }

              final anonymouslyShowDriveDetail = state is! ProfileLoggedIn &&
                  canAnonymouslyShowDriveDetail(state);

              // If the user is not already signing in, not viewing a shared file
              // and not anonymously viewing a drive, redirect them to sign in.
              //
              // Additionally, redirect the user to sign in if they are logging out.
              //
              // `/view/{txId}` is anonymous for the same reason a shared file
              // link is: a recipient who was sent a link has no account and
              // needs none.
              final showingAnonymousRoute = anonymouslyShowDriveDetail ||
                  isViewingSharedFile ||
                  isViewingRawTransaction;

              // Never for somebody who is already signed in. Without that
              // check this fired on *every* profile emission - a sync
              // finishing, a drive being selected, anything that makes
              // `ProfileCubit` republish - setting `signingIn` for a signed-in
              // user, which the block below then cleared while taking
              // `showingDrivesList` with it. The result was a user thrown back
              // to the drives list at random moments, and a `showDrivesList`
              // whose early return then found the flag already set and did
              // nothing, so neither the nav entry nor the breadcrumb worked.
              if (state is! ProfileLoggedIn &&
                  !signingIn &&
                  !gettingStarted &&
                  (!showingAnonymousRoute || state is ProfileLoggingOut)) {
                signingIn = true;
                gettingStarted = false;
                notifyListeners();
              }

              if (state is ProfileLoggingOut) {
                driveId = null;
                driveName = null;
                sharedDriveKey = null;
                notifyListeners();
              }

              // Redirect the user away from sign in if they are already signed in.
              if ((signingIn || gettingStarted) && state is ProfileLoggedIn) {
                signingIn = false;
                gettingStarted = false;

                // And land on the list of drives rather than inside one the
                // app has not looked at yet. Only when there is nothing else
                // to honour: a deep link - a drive, a folder, a shared file, a
                // raw transaction - has already set its target in
                // `setNewRoutePath`, and is left exactly as it was.
                if (!hasARouteToHonour && !showingNames && !showingWebPages) {
                  showingDrivesList = true;
                }

                notifyListeners();
              }
            },
            builder: (context, state) {
              profileCubit = context.read<ProfileCubit>();

              Widget? shell;

              // What the page below is keyed by. A constant key meant the
              // Navigator saw one page whose key never changed however the
              // branch chain resolved, so it kept the route it already had and
              // left the previous screen in place: `showDrivesList` set the
              // flag, `currentConfiguration` reported `/drives`, the address
              // bar changed - and the drive stayed on screen. Named inside
              // each branch rather than derived afterwards, so it cannot drift
              // out of step with the chain that assigns `shell`.
              String shellKey = 'empty';

              final anonymouslyShowDriveDetail =
                  canAnonymouslyShowDriveDetail(state);
              if (PublicationMode.isOn && publication == null) {
                shellKey = 'publicationLoader';
                shell = const PublicationLoaderPage();
              } else if (isViewingSharedFile) {
                shellKey = 'sharedFile';
                shell = BlocProvider<SharedFileCubit>(
                  key: ValueKey(sharedFileId),
                  create: (_) => SharedFileCubit(
                    fileId: sharedFileId!,
                    fileKey: sharedFileKey,
                    linkKeyIsDamaged: sharedFileKeyIsDamaged,
                    // `null` for a v1 link; the cubit then resolves the file
                    // over GraphQL exactly as it always has.
                    linkPayload: sharedFileLinkPayload,
                    arweave: context.read<ArweaveService>(),
                    licenseService: context.read<LicenseService>(),
                  ),
                  child: const SharedFilePage(),
                );
              } else if (isViewingRawTransaction) {
                shellKey = 'rawTransaction';
                // Keyed on the id for the same reason the shared file branch
                // above is: moving between two `/view` links must rebuild the
                // page rather than reuse its state.
                shell = RawTransactionViewPage(
                  key: ValueKey(rawTransactionId),
                  txId: rawTransactionId!,
                  name: rawTransactionName,
                  contentType: rawTransactionContentType,
                );
              } else if (signingIn || signsInWhileChecking(state)) {
                shellKey = 'signIn';
                shell = const LoginPage();
              } else if (gettingStarted) {
                shellKey = 'getStarted';
                shell = const LoginPage(gettingStarted: true);
              } else if (showingNames &&
                  canShowDrivesList(state) &&
                  namesPageIsOn(context)) {
                // The drives list's shape: the sidebar reads an explorer
                // cubit, and a drive chosen in it opens that drive.
                final name = shownName;
                shellKey = name == null ? 'names' : 'name:$name';
                shell = BlocProvider(
                  create: (context) => _driveDetailCubit(context, rootPath),
                  child: ArNSNamesShell(
                    onOpenDrive: openDriveFromList,
                    child: AppShell(
                      page: name == null
                          ? const ArNSNamesPage()
                          : ArNSNamePage(name: name),
                    ),
                  ),
                );
              } else if (showingWebPages &&
                  canShowDrivesList(state) &&
                  webPagesAreOn(context)) {
                shellKey = 'webPages';
                // The Names page's shape, for the same reasons.
                shell = BlocProvider(
                  create: (context) => _driveDetailCubit(context, rootPath),
                  child: WebPagesShell(onOpenDrive: openDriveFromList),
                );
              } else if ((showingDrivesList ||
                      (showingNames && !namesPageIsOn(context)) ||
                      (showingWebPages && !webPagesAreOn(context))) &&
                  canShowDrivesList(state)) {
                shellKey = 'drivesList';
                // A separate subtree from the explorer's, deliberately. The
                // explorer's `DriveDetailCubit` is created once and switched
                // between drives afterwards; sharing one with this page would
                // leave it created against no drive at all, so opening a drive
                // from the list would land in a cubit that never learned which
                // drive it was for. Replacing the subtree builds it against
                // the drive the user actually chose.
                //
                // It still provides one, because the sidebar reads it - and
                // the sidebar does not change here.
                shell = BlocProvider(
                  create: (context) => _driveDetailCubit(context, rootPath),
                  // Above the shell, so the sidebar can read the same cubit the
                  // table does: the sidebar sets which drives are shown and the
                  // table shows them, and they sit on opposite sides of this
                  // boundary.
                  child: DrivesListPage.provide(
                    initialScope: drivesListScope,
                    child: AppShell(
                      page: DrivesListPage(onOpenDrive: openDriveFromList),
                    ),
                  ),
                );
              } else if (state is ProfileLoggedIn ||
                  anonymouslyShowDriveDetail) {
                shellKey = 'explorer';
                driveId = driveId ?? rootPath;

                // Handed over once: the explorer follows it, and later builds
                // pass nothing.
                final routeLink = _routeLink;
                _routeLink = null;

                shell = BlocListener<DrivesCubit, DrivesState>(
                  listener: (context, state) {
                    if (state is DrivesLoadSuccess) {
                      onDriveSelected(state.selectedDriveId);
                      notifyListeners();
                    }
                  },
                  child: BlocProvider(
                    create: (context) => _driveDetailCubit(context, driveId!),
                    child: MultiBlocListener(
                      listeners: [
                        BlocListener<DriveDetailCubit, DriveDetailState>(
                          listener: (context, driveDetailCubitState) {
                            _advancePendingUpload(
                              context,
                              driveDetailCubitState,
                            );

                            final shownDrive = switch (driveDetailCubitState) {
                              DriveDetailLoadSuccess(:final currentDrive) =>
                                currentDrive,
                              DriveDetailLoadUnsynced(:final drive) => drive,
                              _ => null,
                            };

                            if (shownDrive != null) {
                              unawaited(
                                _ensureVisitorHasDriveKey(context, shownDrive),
                              );
                            }

                            if (driveDetailCubitState
                                is DriveDetailLoadSuccess) {
                              driveId = driveDetailCubitState.currentDrive.id;
                              driveFolderId =
                                  driveDetailCubitState.folderInView.folder.id;

                              // The info the drives list asked for, now that
                              // there is a loaded drive to ask. Cleared first,
                              // so a rebuild cannot open it twice.
                              if (_pendingInfoDriveId ==
                                  driveDetailCubitState.currentDrive.id) {
                                _pendingInfoDriveId = null;

                                context.read<DriveDetailCubit>().selectDataItem(
                                      DriveDataTableItemMapper.fromDrive(
                                        driveDetailCubitState.currentDrive,
                                        (_) => null,
                                        0,
                                        driveDetailCubitState
                                                .currentDrive.ownerAddress ==
                                            context
                                                .read<ArDriveAuth>()
                                                .currentUser
                                                .walletAddress,
                                      ),
                                    );
                              }

                              //Can be null at the root folder of the drive
                              notifyListeners();
                            } else if (driveDetailCubitState
                                is DriveDetailLoadNotFound) {
                              // A publication's drive is the one it imported; there
                              // is nothing to attach.
                              if (PublicationMode.isOn) return;

                              // Do not prompt the user to attach an unfound drive if they are logging out.
                              final profileCubit = context.read<ProfileCubit>();

                              if (profileCubit.state is ProfileLoggingOut) {
                                logger.d(
                                    'Drive not found, but user is logging out. Not prompting to attach drive.');

                                clearState();

                                return;
                              }

                              final driveDao = context.read<DriveDao>();
                              final linkedDriveId = driveId!;

                              // One of the user's own private drives that
                              // this session can't open. There is nothing to
                              // attach: the page offers Unlock. A link that
                              // carries the drive's key still attaches.
                              if (sharedDriveKey == null &&
                                  context
                                      .read<DriveUnlockSession>()
                                      .isLocked(linkedDriveId)) {
                                return;
                              }

                              attachDrive(
                                context: context,
                                driveId: driveId,
                                driveName: driveName,
                                driveKey: sharedDriveKey,
                              ).then((_) async {
                                sharedDriveKey = null;
                                sharedRawDriveKey = null;

                                // An attached drive stays the one in view. For
                                // a visitor with no profile it is the only
                                // thing keeping the explorer on screen: let go
                                // of it and the explorer, the sync it just
                                // started and the drives cubit that would have
                                // selected the drive are all torn down, leaving
                                // the visitor on a blank page.
                                //
                                // When the drive was not attached (the dialog
                                // was cancelled, or the drive could not be
                                // found or opened), the link has nothing left
                                // to show, so the user lands where a sign in
                                // lands: the drives list, or the sign in page
                                // for a visitor.
                                final attached = await driveDao
                                        .driveById(driveId: linkedDriveId)
                                        .getSingleOrNull() !=
                                    null;

                                landAfterAttachPrompt(
                                  attached: attached,
                                  loggedIn: canShowDrivesList(
                                    profileCubit.state,
                                  ),
                                );
                              });
                            }
                          },
                        ),
                      ],
                      child: _RouteLinkFollower(
                        link: routeLink,
                        onFollow: (context, link, {required explorerIsNew}) {
                          _startSyncOnOpen(
                            context.read<SyncCubit>(),
                            link.driveId,
                          );
                          followRouteLink(
                            link,
                            driveDetail: context.read<DriveDetailCubit>(),
                            drives: context.read<DrivesCubit>(),
                            explorerIsNew: explorerIsNew,
                          );
                        },
                        child: AppShell(
                          page: DriveDetailPage(
                            context: navigatorKey.currentContext!,
                            anonymouslyShowDriveDetail:
                                anonymouslyShowDriveDetail,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              shell ??= const SizedBox();

              // Which branch won, and the state that decided it. When Home
              // appears not to work this line is the difference between
              // knowing and guessing.
              logger.d(
                'router: shell=$shellKey profile=${state.runtimeType} '
                'showingDrivesList=$showingDrivesList driveId=$driveId',
              );

              final navigator = Navigator(
                key: navigatorKey,
                pages: [
                  MaterialPage(
                    // One page, one key. Keying this by which shell is on
                    // screen made the Navigator *replace* the route on every
                    // move between the drives list and a drive - tearing down
                    // the sidebar and the top bar along with the body, which
                    // reads as the whole page reloading rather than the middle
                    // of it changing.
                    //
                    // It was added when the router's rebuilt tree was being
                    // discarded, before that turned out to be
                    // `Overlay.initialEntries` in `ArDriveAppWithDevTools`.
                    // With the real cause fixed the route updates its child on
                    // its own, so the key goes back to being a constant.
                    key: const ValueKey('AppShell'),
                    child: shell,
                  ),
                ],
                onPopPage: (route, result) {
                  if (!route.didPop(result)) {
                    return false;
                  }

                  notifyListeners();
                  return true;
                },
              );

              if (state is ProfileLoggedIn || anonymouslyShowDriveDetail) {
                return MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (context) => SyncCubit(
                        syncRepository: context.read<SyncRepository>(),
                        activityTracker: context.read<ActivityTracker>(),
                        configService: context.read<ConfigService>(),
                        profileCubit: context.read<ProfileCubit>(),
                        activityCubit: context.read<ActivityCubit>(),
                        promptToSnapshotBloc:
                            context.read<PromptToSnapshotBloc>(),
                        tabVisibility: TabVisibilitySingleton(),
                        userPreferencesRepository:
                            context.read<UserPreferencesRepository>(),
                      ),
                    ),
                    BlocProvider(
                      create: (context) => DrivesCubit(
                        activityTracker: context.read<ActivityTracker>(),
                        auth: context.read<ArDriveAuth>(),
                        initialSelectedDriveId: driveId,
                        profileCubit: context.read<ProfileCubit>(),
                        driveDao: context.read<DriveDao>(),
                        promptToSnapshotBloc:
                            context.read<PromptToSnapshotBloc>(),
                        userPreferencesRepository:
                            context.read<UserPreferencesRepository>(),
                        syncCubit: context.read<SyncCubit>(),
                        unlockSession: context.read<DriveUnlockSession>(),
                      ),
                    ),
                    BlocProvider<PrivateDriveMigrationBloc>(
                      create: (context) => PrivateDriveMigrationBloc(
                        drivesCubit: context.read<DrivesCubit>(),
                        driveDao: context.read<DriveDao>(),
                        ardriveAuth: context.read<ArDriveAuth>(),
                        crypto: ArDriveCrypto(),
                        turboUploadService: context.read<TurboUploadService>(),
                        arweave: context.read<ArweaveService>(),
                        driveUnlocker: context.read<DriveUnlocker>(),
                      ),
                    ),
                  ],
                  child: BlocListener<SyncCubit, SyncState>(
                    listener: (context, state) {
                      if (state is SyncFailure) {
                        final typography = ArDriveTypographyNew.of(context);
                        final colorTokens =
                            ArDriveTheme.of(context).themeData.colorTokens;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              appLocalizationsOf(context).failedToSyncDrive,
                              style: typography.paragraphNormal(
                                color: colorTokens.textHigh,
                              ),
                            ),
                            backgroundColor: colorTokens.containerL3,
                            action: SnackBarAction(
                              label: appLocalizationsOf(context)
                                  .tryAgainEmphasized,
                              backgroundColor: colorTokens.containerL3,
                              textColor: colorTokens.textHigh,
                              onPressed: () =>
                                  context.read<SyncCubit>().startSync(),
                            ),
                          ),
                        );
                      }
                    },
                    child: ArNSResumeScope(
                      child: SearchScope(child: navigator),
                    ),
                  ),
                );
              } else {
                return navigator;
              }
            },
          ),
        ),
      ),
    );
  }

  /// Starts the sync of a drive a visitor just opened, once, now that there
  /// is a `SyncCubit` to start it on.
  ///
  /// `startSyncForDrive` marks the drive as syncing before its first await,
  /// so an explorer cubit built right after finds a sync touching its drive
  /// and waits on the loading panel rather than showing "Drive not synced".
  /// Called from the explorer's cubit factory, which covers an explorer built
  /// fresh for the drive, and from the route-link follower, which covers an
  /// explorer that was already open on another drive.
  ///
  /// `startSyncForDrive` refuses while another sync runs - a visitor opening
  /// a second drive while the first still syncs - so a refusal waits for that
  /// sync to end and tries once more.
  void _startSyncOnOpen(SyncCubit syncCubit, String driveId) {
    if (_syncOnOpenDriveId != driveId) {
      return;
    }

    _syncOnOpenDriveId = null;
    unawaited(() async {
      if (await syncCubit.startSyncForDrive(driveId: driveId)) {
        return;
      }

      await syncCubit.waitCurrentSync();

      if (syncCubit.isClosed ||
          await syncCubit.startSyncForDrive(driveId: driveId)) {
        return;
      }

      logger.w('Opened drive $driveId was not synced; the explorer will '
          'offer to sync it.');
    }());
  }

  DriveDetailCubit _driveDetailCubit(BuildContext context, String driveId) {
    _startSyncOnOpen(context.read<SyncCubit>(), driveId);

    return DriveDetailCubit(
      driveRepository: DriveRepository(
        driveDao: context.read<DriveDao>(),
        auth: context.read<ArDriveAuth>(),
      ),
      activityTracker: context.read<ActivityTracker>(),
      driveId: driveId,
      initialFolderId: driveFolderId,
      initialSelectedItemId: _takeSelectedItemFor(driveId),
      profileCubit: context.read<ProfileCubit>(),
      driveDao: context.read<DriveDao>(),
      configService: context.read<ConfigService>(),
      auth: context.read<ArDriveAuth>(),
      breadcrumbBuilder: BreadcrumbBuilder(
        context.read<FolderRepository>(),
      ),
      syncCubit: context.read<SyncCubit>(),
      publicationScopeRootFolderId: publication?.scopeRootFolderId,
    );
  }

  /// Leaves the drives list for the drive the user picked out of it.
  ///
  /// Called by the page rather than listened for here: the drives cubit
  /// selects a drive on its own as soon as the list loads, and treating that
  /// as navigation would close the page before it had been read. The page
  /// knows which selections came from a person - a row, or the sidebar - and
  /// only those reach this.
  ///
  /// Navigation and nothing else. Opening a drive from the list also fetches
  /// it when nothing has walked it yet, but that decision is not made here and
  /// cannot be: it needs the drive's sync state, and this method has no
  /// context to read it from. It is made one step earlier, by
  /// Opening never starts one: a tap is a request to look at something, not
  /// to fetch it, and a drive with nothing local lands on the card that says
  /// so and carries its own Sync button.
  /// `drives_list_open_never_syncs_test.dart` holds that.
  /// Hands the waiting selection to the cubit being built, if it is that
  /// cubit's, and only once.
  ///
  /// Read at construction rather than kept as route state: a file to highlight
  /// describes one arrival at one folder, not where the reader currently is.
  String? _takeSelectedItemFor(String driveId) {
    if (_selectedItemForFolderDriveId != driveId) {
      return null;
    }

    final itemId = _selectedItemForFolder;
    _selectedItemForFolder = null;
    _selectedItemForFolderDriveId = null;

    return itemId;
  }

  /// [_takeSelectedItemFor], for tests. The real caller is the cubit factory.
  @visibleForTesting
  String? takeSelectedItemForTest(String driveId) =>
      _takeSelectedItemFor(driveId);

  /// Asks for a drive's info panel to open once that drive has loaded.
  ///
  /// Separate from [openDriveFromList] so the drives list keeps one way in: a
  /// row tap and an Info tap both go through the drives cubit's selection and
  /// arrive here by the same road. Only the intent differs, and it is set
  /// before the selection rather than threaded through it.
  void requestDriveInfo(String driveId) {
    _pendingInfoDriveId = driveId;
  }

  /// Asks for an upload to start once its drive has opened.
  ///
  /// Set before the drive is selected, like [requestDriveInfo]. A second
  /// request replaces the first: only the latest press is still wanted.
  void requestUpload(UploadRequest request) {
    _pendingUpload = request;
    _pendingUploadExpiry?.cancel();
    _pendingUploadExpiry = Timer(uploadWaitLimit, _dropPendingUpload);
  }

  void _dropPendingUpload() {
    _pendingUploadExpiry?.cancel();
    _pendingUploadExpiry = null;
    _pendingUpload = null;
  }

  /// Moves a waiting upload along as its drive reports in.
  ///
  /// Everything it can do happens once: the dialog for a drive that is open,
  /// the sync for one nothing has read, or nothing at all. Only a drive still
  /// opening leaves the request standing, so a rebuild cannot act twice and a
  /// later visit to the same drive does nothing.
  void _advancePendingUpload(BuildContext context, DriveDetailState state) {
    final request = _pendingUpload;

    if (request == null) {
      return;
    }

    if (!actOnUpload(context, request: request, detailState: state)) {
      _dropPendingUpload();
    }
  }

  /// Asks for a drive to open at a particular folder, once it is selected.
  ///
  /// The road a search result takes off the drives list. The explorer navigates
  /// a result by calling `openFolder` on its own `DriveDetailCubit`, which works
  /// there because that cubit is long-lived and switches drives underneath the
  /// page. On the drives list it is not: selecting a drive replaces the whole
  /// subtree, so the cubit the modal was handed is torn down mid-navigation and
  /// the reader lands at the drive root instead of the file they searched for.
  ///
  /// Set before the selection, like [requestDriveInfo], and honoured by
  /// [onDriveSelected] when that drive arrives. One shot, so navigating away and
  /// back lands at the root rather than jumping to a folder somebody visited
  /// once.
  void requestFolder(String driveId, String folderId, {String? itemId}) {
    _requestedFolderDriveId = driveId;
    _requestedFolderId = folderId;
    _requestedItemId = itemId;
  }

  @visibleForTesting
  void openDriveFromList(String driveId) {
    showingDrivesList = false;
    showingNames = false;
    showingWebPages = false;
    this.driveId = driveId;

    // A row tap has no folder in view and opens the drive at its root. A search
    // result does have one, and asked for it through [requestFolder] a moment
    // ago - so clearing unconditionally, as this did, threw that away and landed
    // the reader at the root of the right drive rather than at the file they
    // searched for.
    //
    // This is the road that actually runs from the list: `OpenDriveOnSelection`
    // hears the selection and calls here. `onDriveSelected` honours the same
    // request for the explorer, but it is only mounted on the explorer's branch,
    // so it never sees a drive opened from the list.
    if (_requestedFolderDriveId == driveId) {
      driveFolderId = _requestedFolderId;
      _selectedItemForFolder = _requestedItemId;
      _selectedItemForFolderDriveId = driveId;
    } else {
      driveFolderId = null;
    }

    // One shot either way, honoured or not. The folder *link* is discarded
    // here too, which is the older rule this must not disturb: a row tap opens
    // a drive at its root, whatever link the reader arrived through.
    _requestedFolderDriveId = null;
    _requestedFolderId = null;
    _requestedItemId = null;
    _pendingFolderDriveId = null;
    _pendingFolderId = null;
    // Not the info request: opening the drive is how it reaches somewhere it
    // can be honoured. The explorer clears it once the drive has loaded.

    notifyListeners();
  }

  /// Back to the list of drives - the same place a login lands.
  ///
  /// `showingDrivesList` was set in exactly one place, on login, so once a
  /// drive had been opened the list was unreachable without the browser's back
  /// button or typing `/drives`. A landing page you cannot return to is not a
  /// landing page.
  ///
  /// It sets the same one flag the login path sets, on this same delegate, so
  /// the two arrive at one state rather than at two that resemble each other.
  /// [currentConfiguration] then reads `/drives`, which is what makes the
  /// address bar, a bookmark and the browser's own back and forward agree with
  /// what is on screen.
  ///
  /// [driveId] is deliberately left alone: the sidebar has to show something
  /// selected, and the drive the user came from is the right thing for it to
  /// show - going back into it costs one tap. [driveFolderId] is left alone
  /// for the same reason, so that tap lands where they were rather than at the
  /// drive's root.
  ///
  /// A no-op when the list is already what is on screen, so a second tap does
  /// not push a second identical history entry for the browser's back button
  /// to have to walk back through.
  void showDrivesList({DriveScope scope = DriveScope.all}) {
    // No early return. There is no condition this method can test that proves
    // the drives list is what the user is looking at, and every version of
    // that guess has ended the same way: the flag reads true, the request is
    // dropped in silence, and Home is dead for the rest of the session with
    // the address bar insisting `/drives` over a drive.
    //
    // The cost of always honouring it is at worst one repeated history entry.
    // The cost of guessing wrong is a navigation control that does nothing.
    logger.d(
      'showDrivesList: was showingDrivesList=$showingDrivesList '
      'signingIn=$signingIn gettingStarted=$gettingStarted '
      'driveId=$driveId sharedFileId=$sharedFileId '
      'rawTransactionId=$rawTransactionId',
    );

    // Asked for, so nothing outranks it.
    showingDrivesList = true;
    drivesListScope = scope;
    showingNames = false;
    showingWebPages = false;
    signingIn = false;
    gettingStarted = false;
    // Going back to the list abandons whatever a search asked for - all of it,
    // in both the states it can be in. A request honoured in a frame where the
    // explorer never built would otherwise sit here and highlight a stale file
    // the next time that drive opened; one never honoured at all would sit in
    // the other three fields and jump a later, unrelated row tap into a folder
    // somebody searched for once.
    //
    // No live path is known to reach the second - `requestFolder` is always
    // followed immediately by the selection that spends it. This is here
    // because clearing half the state and describing it as all of it is how
    // the first case got missed.
    _requestedFolderDriveId = null;
    _requestedFolderId = null;
    _requestedItemId = null;
    _selectedItemForFolder = null;
    _selectedItemForFolderDriveId = null;
    sharedFileId = null;
    sharedFileKey = null;
    sharedRawFileKey = null;
    sharedFileLinkPayload = null;
    sharedFileKeyIsDamaged = false;
    rawTransactionId = null;
    rawTransactionName = null;
    rawTransactionContentType = null;

    notifyListeners();
  }

  /// The Names page, or [name]'s own page, from the nav's Names heading.
  /// Like [showDrivesList], the drive in the sidebar stays selected
  /// underneath.
  void showNames({String? name}) {
    showingNames = true;
    shownName = name;
    showingWebPages = false;
    _leaveForAPage();
  }

  /// The Web pages page, from the nav's Web pages heading.
  void showWebPages() {
    showingWebPages = true;
    showingNames = false;
    _leaveForAPage();
  }

  /// What the Names and Web pages pages leave behind: every other screen.
  void _leaveForAPage() {
    showingDrivesList = false;
    signingIn = false;
    gettingStarted = false;
    _requestedFolderDriveId = null;
    _requestedFolderId = null;
    _requestedItemId = null;
    _selectedItemForFolder = null;
    _selectedItemForFolderDriveId = null;
    sharedFileId = null;
    sharedFileKey = null;
    sharedRawFileKey = null;
    sharedFileLinkPayload = null;
    sharedFileKeyIsDamaged = false;
    rawTransactionId = null;
    rawTransactionName = null;
    rawTransactionContentType = null;
    notifyListeners();
  }

  /// Whether the Web pages page can be shown: where Publish to web is
  /// (`offersPublishToWeb`), outside a publication with publishing on. Not
  /// web-only: deployments are on the web from any platform.
  static bool webPagesAreOn(BuildContext context) {
    if (PublicationMode.isOn) return false;
    try {
      return context.read<ConfigService>().config.enableDriveStatePublishing;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// Whether the Names page can be shown: names on, outside a publication.
  static bool namesPageIsOn(BuildContext context) {
    if (PublicationMode.isOn) return false;
    try {
      return context.read<ConfigService>().config.enableArNS;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// Where the user goes once the attach prompt a drive link opened is closed.
  ///
  /// An attached drive stays in view. Otherwise the link has nothing left to
  /// show: a logged-in user lands on the drives list, the same place a sign in
  /// lands when there is no link to honour, and a visitor goes to the sign in
  /// page, because the explorer only renders for a visitor while a drive is
  /// being viewed. Without this the explorer had no drive to show and the
  /// visitor's builder fell through to an empty page.
  @visibleForTesting
  void landAfterAttachPrompt({
    required bool attached,
    required bool loggedIn,
  }) {
    if (attached) {
      notifyListeners();
      return;
    }

    driveId = null;
    driveName = null;
    driveFolderId = null;
    _pendingFolderDriveId = null;
    _pendingFolderId = null;
    _routeLink = null;
    _pendingInfoDriveId = null;
    sharedDriveKey = null;
    sharedRawDriveKey = null;

    if (loggedIn) {
      showDrivesList();
    } else {
      signingIn = true;
      gettingStarted = false;
      showingDrivesList = false;
      notifyListeners();
    }
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    _routeKnown = true;
    if (PublicationMode.isOn) {
      _publicationFolderRequest = configuration.publicationFolderId;
      _publicationFileRequest = configuration.publicationFileId;
      // A file page's key comes only from its link; a route without one
      // (a reload reports it back) leaves the one the link gave. A damaged
      // one is kept as damaged, so the page says so.
      if (configuration.sharedRawFileKey != null ||
          configuration.sharedFileKeyIsDamaged) {
        sharedFileKey = configuration.sharedFileKey;
        sharedRawFileKey = configuration.sharedRawFileKey;
        sharedFileKeyIsDamaged = configuration.sharedFileKeyIsDamaged;
      }
      // Before the publication is in, [openPublication] follows it.
      if (publication != null && publication?.scope is! PublicationFileScope) {
        await _followPublicationLink();
      }
      return;
    }

    signingIn = configuration.signingIn;
    gettingStarted = configuration.getStarted;
    showingDrivesList = configuration.drivesList;
    showingNames = configuration.names;
    shownName = configuration.names ? configuration.arnsName : null;
    showingWebPages = configuration.webPages;
    drivesListScope = DriveScope.all;
    driveId = configuration.driveId;
    driveName = configuration.driveName;
    driveFolderId = configuration.driveFolderId;
    _pendingFolderDriveId =
        configuration.driveFolderId == null ? null : configuration.driveId;
    _pendingFolderId = configuration.driveFolderId;
    _routeLink = configuration.driveId == null ||
            configuration.drivesList ||
            configuration.names ||
            configuration.webPages
        ? null
        : RouteLink(
            driveId: configuration.driveId!,
            folderId: configuration.driveFolderId,
          );
    sharedDriveKey = configuration.sharedDriveKey;
    sharedRawDriveKey = configuration.sharedRawDriveKey;
    _sharedDriveKeyDriveId =
        configuration.sharedDriveKey == null ? null : configuration.driveId;
    _keyPromptedForDriveId = null;
    sharedFileId = configuration.sharedFileId;
    sharedFileKey = configuration.sharedFileKey;
    sharedRawFileKey = configuration.sharedRawFileKey;
    sharedFileKeyIsDamaged = configuration.sharedFileKeyIsDamaged;
    sharedFileLinkPayload = configuration.sharedFileLinkPayload;
    rawTransactionId = configuration.rawTransactionId;
    rawTransactionName = configuration.rawTransactionName;
    rawTransactionContentType = configuration.rawTransactionContentType;

    // A visitor who goes somewhere only an account can see, in the same tab
    // (`#/` after a share page, say), changes no profile state, so the
    // listener in [build] that sends visitors to sign in never runs. No branch
    // of the builder had anything to draw and the splash stayed up. The same
    // rule is applied here. Not while the check for an account or a login is
    // under way: those end in a profile change, which the listener handles.
    final profileState = profileCubit?.state;
    if (profileState != null &&
        profileState is! ProfileLoggedIn &&
        profileState is! ProfileCheckingAvailability &&
        profileState is! ProfileLoggingIn &&
        !signingIn &&
        !gettingStarted &&
        !canAnonymouslyShowDriveDetail(profileState) &&
        !isViewingSharedFile &&
        !isViewingRawTransaction) {
      signingIn = true;
    }
  }

  /// Brings the explorer to the drive and folder the address bar named.
  ///
  /// An explorer built for this link has already opened it, and only the
  /// sidebar's drive has to follow. One that was already open opens it here.
  /// Either way the drive is selected through [DrivesCubit], as a click on it
  /// in the sidebar would be, so the sidebar shows it and the next refresh of
  /// the drive list does not take the explorer back to the drive it showed
  /// before.
  @visibleForTesting
  void followRouteLink(
    RouteLink link, {
    required DriveDetailCubit driveDetail,
    required DrivesCubit drives,
    required bool explorerIsNew,
  }) {
    if (!explorerIsNew) {
      driveDetail.followLink(driveId: link.driveId, folderId: link.folderId);
    }

    final drivesState = drives.state;

    if (drivesState is! DrivesLoadSuccess || drivesState.hasNoDrives) {
      // A visitor with no drives yet. Selecting a drive among none only shows
      // the no-drives screen, so the explorer is sent there itself, which
      // offers to attach the drive.
      if (!explorerIsNew && driveDetail.currentDriveId != link.driveId) {
        driveDetail.changeDrive(link.driveId);
      }
      return;
    }

    if (drivesState.selectedDriveId != link.driveId) {
      drives.selectDrive(link.driveId);
      return;
    }

    // The drive was selected already, so no selection is coming to spend the
    // folder held for it. Left standing, the next refresh of the drive list
    // would put that folder back in the address bar wherever the reader had
    // gone since.
    _pendingFolderDriveId = null;
    _pendingFolderId = null;
  }

  /// Shows a drive somebody opened from the sign-in screen, without a profile.
  ///
  /// The drive row is already written by the time this is called, so the
  /// explorer finds it and no attach prompt opens. A private drive's key is
  /// already in memory. It is never put in the address bar: a key somebody
  /// typed would otherwise sit in the browser's history. A reload asks for it
  /// once instead.
  void openDriveAsVisitor({
    required String driveId,
    String? folderId,
    DriveKey? driveKey,
  }) {
    signingIn = false;
    gettingStarted = false;
    showingDrivesList = false;
    showingNames = false;
    showingWebPages = false;

    this.driveId = driveId;
    driveName = null;
    driveFolderId = folderId;
    _pendingFolderDriveId = folderId == null ? null : driveId;
    _pendingFolderId = folderId;
    _routeLink = RouteLink(driveId: driveId, folderId: folderId);

    sharedDriveKey = driveKey;
    sharedRawDriveKey = null;
    _sharedDriveKeyDriveId = driveKey == null ? null : driveId;

    _syncOnOpenDriveId = driveId;
    _keyPromptedForDriveId = null;

    notifyListeners();
  }

  /// Follows a link that is not a drive - a shared file, a raw transaction -
  /// from the sign-in screen. Both pages render for a visitor already.
  Future<void> openRouteAsVisitor(AppRoutePath route) async {
    await setNewRoutePath(route);
    notifyListeners();
  }

  /// Takes a visitor to the sign-in page and keeps the drive they were
  /// viewing, so a login lands back on it. Logging out instead would run
  /// [clearState] and drop the drive.
  void signInKeepingDrive() {
    signingIn = true;
    gettingStarted = false;
    showingDrivesList = false;
    showingNames = false;
    showingWebPages = false;
    notifyListeners();
  }

  /// A visitor's private drive needs its key in memory for anything to
  /// decrypt. The key is there when the drive was just opened or attached; it
  /// is not after a reload. Then a share link may still carry it, and if it
  /// does not, or the key does not open this drive, the reader is asked for
  /// it once. Cancelling that lands on the sign-in screen, because the
  /// explorer has nothing it can show.
  ///
  /// A link's key is checked against the drive before it goes into memory:
  /// whatever is in memory when the visitor signs in is stored on the row
  /// ([DriveDao.persistInMemoryDriveKeys]), and a wrong key stored there
  /// would break the drive for that account until it is attached again.
  Future<void> _ensureVisitorHasDriveKey(
    BuildContext context,
    Drive drive,
  ) async {
    if (!drive.isPrivate ||
        _keyPromptedForDriveId == drive.id ||
        context.read<ProfileCubit>().state is ProfileLoggedIn) {
      return;
    }

    final driveDao = context.read<DriveDao>();

    if (await driveDao.getDriveKeyFromMemory(drive.id) != null) {
      return;
    }

    final linkKey = _sharedDriveKeyDriveId == drive.id ? sharedDriveKey : null;

    if (linkKey != null) {
      if (!context.mounted) return;

      if (await _keyOpensDrive(
          context.read<ArweaveService>(), drive, linkKey)) {
        await driveDao.putDriveKeyInMemory(
          driveID: drive.id,
          driveKey: linkKey,
        );
        return;
      }
    }

    if (!context.mounted || _keyPromptedForDriveId == drive.id) {
      return;
    }

    _keyPromptedForDriveId = drive.id;

    try {
      await attachDrive(context: context, driveId: drive.id);
    } catch (e) {
      // Another dialog held the screen. The prompt never opened, so the next
      // state the explorer emits asks again.
      logger.w('Could not ask for the key of drive ${drive.id}: $e');
      _keyPromptedForDriveId = null;
      return;
    }

    // Attaching put the key in memory and started the drive's sync, or the
    // prompt was cancelled and the explorer has nothing it can show: the same
    // landing the attach prompt a link opened uses.
    landAfterAttachPrompt(
      attached: await driveDao.getDriveKeyFromMemory(drive.id) != null,
      loggedIn: false,
    );
  }

  /// Whether [key] decrypts [drive]'s latest metadata, read from its owner.
  /// A network failure counts as no: the reader is asked for the key instead.
  Future<bool> _keyOpensDrive(
    ArweaveService arweave,
    Drive drive,
    DriveKey key,
  ) async {
    try {
      final entity = await arweave.getLatestDriveEntityWithId(
        drive.id,
        driveKey: key.key,
        driveOwner: drive.ownerAddress,
      );

      return entity != null;
    } catch (e) {
      logger.w('Could not check the link key for drive ${drive.id}: $e');
      return false;
    }
  }

  void clearState() {
    signingIn = true;
    gettingStarted = false;
    showingDrivesList = false;
    showingNames = false;
    showingWebPages = false;
    driveId = null;
    driveName = null;
    driveFolderId = null;
    _pendingFolderDriveId = null;
    _pendingFolderId = null;
    _routeLink = null;
    _syncOnOpenDriveId = null;
    _keyPromptedForDriveId = null;
    _sharedDriveKeyDriveId = null;
    _pendingInfoDriveId = null;
    _dropPendingUpload();
    // A search somebody ran before logging out is not an instruction to the
    // next person to sign in on this device. Every other pending field here is
    // cleared for the same reason.
    _requestedFolderDriveId = null;
    _requestedFolderId = null;
    _requestedItemId = null;
    _selectedItemForFolder = null;
    _selectedItemForFolderDriveId = null;
    sharedDriveKey = null;
    sharedRawDriveKey = null;
    sharedFileId = null;
    sharedFileKey = null;
    sharedRawFileKey = null;
    sharedFileKeyIsDamaged = false;
    sharedFileLinkPayload = null;
    rawTransactionId = null;
    rawTransactionName = null;
    rawTransactionContentType = null;
  }
}

extension RouterExtensions on Router {
  AppRouterDelegate get delegate => routerDelegate as AppRouterDelegate;
}

/// A drive, and a folder in it, named by the address bar.
@immutable
class RouteLink {
  const RouteLink({required this.driveId, this.folderId});

  final String driveId;

  /// `null` for a drive link, which opens the drive at its root.
  final String? folderId;
}

/// Passes the explorer each [RouteLink] the router hands it, once, after the
/// frame that brought it.
///
/// After the frame because following a link emits from the explorer's cubits,
/// and their listeners rebuild widgets that are being built right now.
class _RouteLinkFollower extends StatefulWidget {
  const _RouteLinkFollower({
    required this.link,
    required this.onFollow,
    required this.child,
  });

  final RouteLink? link;
  final void Function(
    BuildContext context,
    RouteLink link, {
    required bool explorerIsNew,
  }) onFollow;
  final Widget child;

  @override
  State<_RouteLinkFollower> createState() => _RouteLinkFollowerState();
}

class _RouteLinkFollowerState extends State<_RouteLinkFollower> {
  @override
  void initState() {
    super.initState();
    _follow(widget.link, explorerIsNew: true);
  }

  @override
  void didUpdateWidget(_RouteLinkFollower oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.link, oldWidget.link)) {
      _follow(widget.link, explorerIsNew: false);
    }
  }

  void _follow(RouteLink? link, {required bool explorerIsNew}) {
    if (link == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onFollow(context, link, explorerIsNew: explorerIsNew);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
