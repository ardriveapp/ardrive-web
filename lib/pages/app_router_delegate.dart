import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
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
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive/drive_explorer/dock/ardrive_dock.dart';
import 'package:ardrive/drive_explorer/multi_thumbnail_creation/multi_thumbnail_creation_modal.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_page.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
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

  /// The standing request, for tests. The explorer clears it as it honours it.
  @visibleForTesting
  String? get pendingInfoDriveId => _pendingInfoDriveId;

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

  bool canAnonymouslyShowDriveDetail(ProfileState profileState) =>
      profileState is ProfileUnavailable && tryingToViewDrive;

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
  AppRoutePath get currentConfiguration => AppRoutePath(
        signingIn: signingIn,
        getStarted: gettingStarted,
        drivesList: showingDrivesList,
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
    return ArDriveAppWithDevTools(widget: _app());
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
                if (!hasARouteToHonour) {
                  showingDrivesList = true;
                }

                notifyListeners();
              }
            },
            builder: (context, state) {
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
              if (isViewingSharedFile) {
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
              } else if (signingIn) {
                shellKey = 'signIn';
                shell = const LoginPage();
              } else if (gettingStarted) {
                shellKey = 'getStarted';
                shell = const LoginPage(gettingStarted: true);
              } else if (showingDrivesList && canShowDrivesList(state)) {
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
                  child: AppShell(
                    page: DrivesListPage(onOpenDrive: openDriveFromList),
                  ),
                );
              } else if (state is ProfileLoggedIn ||
                  anonymouslyShowDriveDetail) {
                shellKey = 'explorer';
                driveId = driveId ?? rootPath;

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
                                        driveDetailCubitState.currentDrive
                                                .ownerAddress ==
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
                              // Do not prompt the user to attach an unfound drive if they are logging out.
                              final profileCubit = context.read<ProfileCubit>();

                              if (profileCubit.state is ProfileLoggingOut) {
                                logger.d(
                                    'Drive not found, but user is logging out. Not prompting to attach drive.');

                                clearState();

                                return;
                              }

                              attachDrive(
                                context: context,
                                driveId: driveId,
                                driveName: driveName,
                                driveKey: sharedDriveKey,
                              ).then((_) {
                                sharedDriveKey = null;
                                sharedRawDriveKey = null;
                                driveId = null;
                                driveName = null;
                                notifyListeners();
                              });
                            }
                          },
                        ),
                      ],
                      child: AppShell(
                        page: DriveDetailPage(
                          context: navigatorKey.currentContext!,
                          anonymouslyShowDriveDetail:
                              anonymouslyShowDriveDetail,
                        ),
                      ),
                    ),
                  ),
                );
              }

              shell ??= const SizedBox();

              final navigator = Navigator(
                key: navigatorKey,
                pages: [
                  MaterialPage(
                    key: ValueKey(shellKey),
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
                    child: navigator,
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

  DriveDetailCubit _driveDetailCubit(BuildContext context, String driveId) {
    return DriveDetailCubit(
      driveRepository: DriveRepository(
        driveDao: context.read<DriveDao>(),
        auth: context.read<ArDriveAuth>(),
      ),
      activityTracker: context.read<ActivityTracker>(),
      driveId: driveId,
      initialFolderId: driveFolderId,
      profileCubit: context.read<ProfileCubit>(),
      driveDao: context.read<DriveDao>(),
      configService: context.read<ConfigService>(),
      auth: context.read<ArDriveAuth>(),
      breadcrumbBuilder: BreadcrumbBuilder(
        context.read<FolderRepository>(),
      ),
      syncCubit: context.read<SyncCubit>(),
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
  /// [DrivesListCubit.syncDriveIfNeverSynced], on every selection that reaches
  /// this - which is every selection a person made, from either surface.
  /// `drives_list_open_syncs_test.dart` holds the two together.
  /// Asks for a drive's info panel to open once that drive has loaded.
  ///
  /// Separate from [openDriveFromList] so the drives list keeps one way in: a
  /// row tap and an Info tap both go through the drives cubit's selection and
  /// arrive here by the same road. Only the intent differs, and it is set
  /// before the selection rather than threaded through it.
  void requestDriveInfo(String driveId) {
    _pendingInfoDriveId = driveId;
  }

  @visibleForTesting
  void openDriveFromList(String driveId) {
    showingDrivesList = false;
    this.driveId = driveId;
    // The list has no folder in view, and the drive opens at its root.
    driveFolderId = null;
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
  void showDrivesList() {
    // Already there, and demonstrably so: the flag alone was not proof. Every
    // route below is checked *before* the drives list in `build`, so with any
    // of them set the list is not what is on screen no matter what the flag
    // says - and returning early on the flag then swallowed the request in
    // silence, which is how both the nav entry and the breadcrumb came to do
    // nothing at all.
    final alreadyShowing = showingDrivesList &&
        !signingIn &&
        !gettingStarted &&
        !isViewingSharedFile &&
        !isViewingRawTransaction;

    if (alreadyShowing) {
      return;
    }

    // Asked for, so nothing outranks it.
    showingDrivesList = true;
    signingIn = false;
    gettingStarted = false;
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

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    signingIn = configuration.signingIn;
    gettingStarted = configuration.getStarted;
    showingDrivesList = configuration.drivesList;
    driveId = configuration.driveId;
    driveName = configuration.driveName;
    driveFolderId = configuration.driveFolderId;
    _pendingFolderDriveId =
        configuration.driveFolderId == null ? null : configuration.driveId;
    _pendingFolderId = configuration.driveFolderId;
    sharedDriveKey = configuration.sharedDriveKey;
    sharedRawDriveKey = configuration.sharedRawDriveKey;
    sharedFileId = configuration.sharedFileId;
    sharedFileKey = configuration.sharedFileKey;
    sharedRawFileKey = configuration.sharedRawFileKey;
    sharedFileKeyIsDamaged = configuration.sharedFileKeyIsDamaged;
    sharedFileLinkPayload = configuration.sharedFileLinkPayload;
    rawTransactionId = configuration.rawTransactionId;
    rawTransactionName = configuration.rawTransactionName;
    rawTransactionContentType = configuration.rawTransactionContentType;
  }

  void clearState() {
    signingIn = true;
    gettingStarted = false;
    showingDrivesList = false;
    driveId = null;
    driveName = null;
    driveFolderId = null;
    _pendingFolderDriveId = null;
    _pendingFolderId = null;
    _pendingInfoDriveId = null;
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
