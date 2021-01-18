import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_shell.dart';

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  bool signingIn;

  String driveId;
  String driveFolderId;

  String sharedFileId;
  SecretKey sharedFileKey;
  String sharedRawFileKey;

  bool canAnonymouslyShowDriveDetail(ProfileState profileState) =>
      profileState is ProfileUnavailable && tryingToViewDrive;
  bool get tryingToViewDrive => driveId != null;
  bool get isViewingSharedFile => sharedFileId != null;

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(
        signingIn: signingIn,
        driveId: driveId,
        driveFolderId: driveFolderId,
        sharedFileId: sharedFileId,
        sharedFileKey: sharedFileKey,
        sharedRawFileKey: sharedRawFileKey,
      );

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  AppRouterDelegate() : navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
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
        },
        builder: (context, state) {
          Widget shell;

          final anonymouslyShowDriveDetail =
              canAnonymouslyShowDriveDetail(state);

          // Show an alert if the screen size is too small as the app is not fully responsive yet.
          final screenNotSupported = MediaQuery.of(context).size.width <= 576;
          if (screenNotSupported) {
            shell = ScreenNotSupportedPage();
          } else if (signingIn) {
            shell = ProfileAuthPage();
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
                Widget shellPage;
                if (state is DrivesLoadSuccess) {
                  shellPage =
                      !state.hasNoDrives ? DriveDetailPage() : NoDrivesPage();
                }

                shellPage ??= const SizedBox();

                return BlocProvider(
                  key: ValueKey(driveId),
                  create: (context) => DriveDetailCubit(
                    driveId: driveId,
                    initialFolderId: driveFolderId,
                    profileCubit: context.read<ProfileCubit>(),
                    driveDao: context.read<DriveDao>(),
                    config: context.read<AppConfig>(),
                  ),
                  child: BlocListener<DriveDetailCubit, DriveDetailState>(
                    listener: (context, state) {
                      if (state is DriveDetailLoadSuccess) {
                        driveId = state.currentDrive.id;
                        driveFolderId = state.currentFolder.folder.id;
                        notifyListeners();
                      } else if (state is DriveDetailLoadNotFound) {
                        // Do not prompt the user to attach an unfound drive if they are logging out.
                        final profileCubit = context.read<ProfileCubit>();
                        if (profileCubit.state is ProfileLoggingOut) {
                          return;
                        }

                        promptToAttachDrive(
                            context: context, initialDriveId: driveId);
                      }
                    },
                    child: FloatingHelpButtonPortalEntry(
                      child: AppShell(page: shellPage),
                    ),
                  ),
                );
              },
            );
          } else if (isViewingSharedFile) {
            shell = BlocProvider<SharedFileCubit>(
              key: ValueKey(sharedFileId),
              create: (_) => SharedFileCubit(
                fileId: sharedFileId,
                fileKey: sharedFileKey,
                arweave: context.read<ArweaveService>(),
              ),
              child: SharedFilePage(),
            );
          }

          shell ??= const SizedBox();

          final navigator = Navigator(
            key: navigatorKey,
            pages: [
              MaterialPage(
                key: ValueKey('AppShell'),
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
                    profileCubit: context.read<ProfileCubit>(),
                    arweave: context.read<ArweaveService>(),
                    driveDao: context.read<DriveDao>(),
                    db: context.read<Database>(),
                  ),
                ),
                BlocProvider(
                  create: (context) => DrivesCubit(
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
                        content: Text('Failed to sync drive contents.'),
                        action: SnackBarAction(
                          label: 'TRY AGAIN',
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
      );

  @override
  Future<void> setNewRoutePath(AppRoutePath path) async {
    signingIn = path.signingIn;
    driveId = path.driveId;
    driveFolderId = path.driveFolderId;
    sharedFileId = path.sharedFileId;
    sharedFileKey = path.sharedFileKey;
    sharedRawFileKey = path.sharedRawFileKey;
  }
}

extension RouterExtensions on Router {
  AppRouterDelegate get delegate => routerDelegate as AppRouterDelegate;
}
