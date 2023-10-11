import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/feedback_survey.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  bool signingIn = false;

  String? driveId;
  String? driveName;
  String? driveFolderId;

  SecretKey? sharedDriveKey;
  String? sharedRawDriveKey;

  String? sharedFileId;
  SecretKey? sharedFileKey;
  String? sharedRawFileKey;

  bool canAnonymouslyShowDriveDetail(ProfileState profileState) =>
      profileState is ProfileUnavailable && tryingToViewDrive;
  bool get tryingToViewDrive => driveId != null;
  bool get tryingToViewSharedPrivateDrive => sharedDriveKey != null;
  bool get isViewingSharedFile => sharedFileId != null;

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(
        signingIn: signingIn,
        driveId: driveId,
        driveName: driveName,
        sharedDriveKey: sharedDriveKey,
        sharedRawDriveKey: sharedRawDriveKey,
        driveFolderId: driveFolderId,
        sharedFileId: sharedFileId,
        sharedFileKey: sharedFileKey,
        sharedRawFileKey: sharedRawFileKey,
      );

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  AppRouterDelegate() : navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    if (context.read<ConfigService>().flavor != Flavor.production) {
      return ArDriveAppWithDevTools(widget: _app());
    }

    return _app();
  }

  Widget _app() {
    return BlocConsumer<ThemeSwitcherBloc, ThemeSwitcherState>(
      listener: (context, state) {
        if (state is ThemeSwitcherDarkTheme) {
          ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.dark);
        } else if (state is ThemeSwitcherLightTheme) {
          ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.light);
        }
      },
      builder: (context, _) => BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          // Clear state to prevent the last drive from being attached on new login
          if (state is ProfileLoggingOut) {
            logger.d('Logging out. Clearing state.');

            clearState();
          }

          final anonymouslyShowDriveDetail =
              state is! ProfileLoggedIn && canAnonymouslyShowDriveDetail(state);

          // If the user is not already signing in, not viewing a shared file and not anonymously viewing a drive,
          // redirect them to sign in.
          //
          // Additionally, redirect the user to sign in if they are logging out.
          final showingAnonymousRoute =
              anonymouslyShowDriveDetail || isViewingSharedFile;

          if (!signingIn &&
              (!showingAnonymousRoute || state is ProfileLoggingOut)) {
            signingIn = true;
            notifyListeners();
          }

          // Redirect the user away from sign in if they are already signed in.
          if (signingIn && state is ProfileLoggedIn) {
            signingIn = false;
            notifyListeners();
          }
          // Cleans up any shared drives from previous sessions
          // TODO: Find a better place to do this
          final lastLoggedInUser =
              state is ProfileLoggedIn ? state.walletAddress : null;
          if (lastLoggedInUser != null) {
            context
                .read<DriveDao>()
                .deleteSharedPrivateDrives(lastLoggedInUser);
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
                arweave: context.read<ArweaveService>(),
              ),
              child: SharedFilePage(),
            );
          } else if (signingIn) {
            shell = const LoginPage();
          } else if (state is ProfileLoggedIn || anonymouslyShowDriveDetail) {
            shell = BlocConsumer<DrivesCubit, DrivesState>(
              listener: (context, state) {
                if (state is DrivesLoadSuccess) {
                  final selectedDriveChanged = driveId != state.selectedDriveId;
                  if (selectedDriveChanged) {
                    driveFolderId = null;
                  }

                  driveId = state.selectedDriveId;
                  notifyListeners();
                }
              },
              builder: (context, state) {
                Widget? shellPage;
                if (state is DrivesLoadSuccess) {
                  shellPage = !state.hasNoDrives
                      ? const DriveDetailPage()
                      : const NoDrivesPage();
                  driveId = state.selectedDriveId;
                }

                shellPage ??= const SizedBox();
                driveId = driveId ?? rootPath;

                return BlocProvider(
                  key: ValueKey(driveId),
                  create: (context) => DriveDetailCubit(
                    driveId: driveId!,
                    initialFolderId: driveFolderId,
                    profileCubit: context.read<ProfileCubit>(),
                    driveDao: context.read<DriveDao>(),
                    configService: context.read<ConfigService>(),
                    auth: context.read<ArDriveAuth>(),
                  ),
                  child: MultiBlocListener(
                    listeners: [
                      BlocListener<DriveDetailCubit, DriveDetailState>(
                        listener: (context, state) {
                          if (state is DriveDetailLoadSuccess) {
                            driveId = state.currentDrive.id;
                            driveFolderId = state.folderInView.folder.id;

                            //Can be null at the root folder of the drive
                            notifyListeners();
                          } else if (state is DriveDetailLoadNotFound) {
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
                            );
                          }
                        },
                      ),
                      BlocListener<FeedbackSurveyCubit, FeedbackSurveyState>(
                        listener: (context, state) {
                          if (state is FeedbackSurveyRemindMe && state.isOpen) {
                            openFeedbackSurveyModal(context);
                          } else if (state is FeedbackSurveyRemindMe &&
                              !state.isOpen) {
                            Navigator.pop(context);
                          } else if (state is FeedbackSurveyDontRemindMe &&
                              !state.isOpen) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                      BlocListener<ProfileCubit, ProfileState>(
                        listener: ((context, state) {
                          if (state is ProfileLoggingOut) {
                            context.read<FeedbackSurveyCubit>().reset();
                          }
                        }),
                      ),
                    ],
                    child: AppShell(
                      page: shellPage,
                    ),
                  ),
                );
              },
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
                    activityTracker: context.read<ActivityTracker>(),
                    configService: context.read<ConfigService>(),
                    profileCubit: context.read<ProfileCubit>(),
                    activityCubit: context.read<ActivityCubit>(),
                    arweave: context.read<ArweaveService>(),
                    driveDao: context.read<DriveDao>(),
                    db: context.read<Database>(),
                    tabVisibility: TabVisibilitySingleton(),
                  ),
                ),
                BlocProvider(
                  create: (context) => DrivesCubit(
                    auth: context.read<ArDriveAuth>(),
                    initialSelectedDriveId: driveId,
                    profileCubit: context.read<ProfileCubit>(),
                    driveDao: context.read<DriveDao>(),
                  ),
                ),
              ],
              child: BlocListener<SyncCubit, SyncState>(
                listener: (context, state) {
                  if (state is SyncFailure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          appLocalizationsOf(context).failedToSyncDrive,
                        ),
                        action: SnackBarAction(
                          label: appLocalizationsOf(context).tryAgainEmphasized,
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
    );
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    signingIn = configuration.signingIn;
    driveId = configuration.driveId;
    driveName = configuration.driveName;
    driveFolderId = configuration.driveFolderId;
    sharedDriveKey = configuration.sharedDriveKey;
    sharedRawDriveKey = configuration.sharedRawDriveKey;
    sharedFileId = configuration.sharedFileId;
    sharedFileKey = configuration.sharedFileKey;
    sharedRawFileKey = configuration.sharedRawFileKey;
  }

  void clearState() {
    signingIn = true;
    driveId = null;
    driveName = null;
    driveFolderId = null;
    sharedDriveKey = null;
    sharedRawDriveKey = null;
    sharedFileId = null;
    sharedFileKey = null;
    sharedRawFileKey = null;
  }
}

extension RouterExtensions on Router {
  AppRouterDelegate get delegate => routerDelegate as AppRouterDelegate;
}
