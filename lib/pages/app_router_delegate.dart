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
import 'package:ardrive/drive_explorer/dock/ardrive_dock.dart';
import 'package:ardrive/drive_explorer/multi_thumbnail_creation/multi_thumbnail_creation_modal.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
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
  bool get tryingToViewDrive => driveId != null;
  bool get tryingToViewSharedPrivateDrive => sharedDriveKey != null;
  bool get isViewingSharedFile => sharedFileId != null;
  bool get isViewingRawTransaction => rawTransactionId != null;

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(
        signingIn: signingIn,
        getStarted: gettingStarted,
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

              if (!signingIn &&
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
                notifyListeners();
              }
            },
            builder: (context, state) {
              Widget? shell;

              final anonymouslyShowDriveDetail =
                  canAnonymouslyShowDriveDetail(state);
              if (isViewingSharedFile) {
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
                shell = const LoginPage();
              } else if (gettingStarted) {
                shell = const LoginPage(gettingStarted: true);
              } else if (state is ProfileLoggedIn ||
                  anonymouslyShowDriveDetail) {
                driveId = driveId ?? rootPath;

                shell = BlocListener<DrivesCubit, DrivesState>(
                  listener: (context, state) {
                    if (state is DrivesLoadSuccess) {
                      onDriveSelected(state.selectedDriveId);
                      notifyListeners();
                    }
                  },
                  child: BlocProvider(
                    create: (context) => DriveDetailCubit(
                      driveRepository: DriveRepository(
                        driveDao: context.read<DriveDao>(),
                        auth: context.read<ArDriveAuth>(),
                      ),
                      activityTracker: context.read<ActivityTracker>(),
                      driveId: driveId!,
                      initialFolderId: driveFolderId,
                      profileCubit: context.read<ProfileCubit>(),
                      driveDao: context.read<DriveDao>(),
                      configService: context.read<ConfigService>(),
                      auth: context.read<ArDriveAuth>(),
                      breadcrumbBuilder: BreadcrumbBuilder(
                        context.read<FolderRepository>(),
                      ),
                      syncCubit: context.read<SyncCubit>(),
                    ),
                    child: MultiBlocListener(
                      listeners: [
                        BlocListener<DriveDetailCubit, DriveDetailState>(
                          listener: (context, driveDetailCubitState) {
                            if (driveDetailCubitState
                                is DriveDetailLoadSuccess) {
                              driveId = driveDetailCubitState.currentDrive.id;
                              driveFolderId =
                                  driveDetailCubitState.folderInView.folder.id;

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

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    signingIn = configuration.signingIn;
    gettingStarted = configuration.getStarted;
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
    driveId = null;
    driveName = null;
    driveFolderId = null;
    _pendingFolderDriveId = null;
    _pendingFolderId = null;
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
