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
  String driveId;
  String driveFolderId;

  String sharedFileId;
  SecretKey sharedFileKey;
  String sharedRawFileKey;

  bool get isViewingDrive => driveId != null;

  bool get isViewingSharedFile => sharedFileId != null;

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(
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
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          Widget shell;

          // Only prompt the user to log in if they do not have a profile and are not trying to view a linked drive.
          final showAuthPage = state is! ProfileLoggedIn &&
              !(state is ProfileUnavailable && isViewingDrive);

          if (isViewingSharedFile) {
            shell = BlocProvider<SharedFileCubit>(
              key: ValueKey(sharedFileId),
              create: (_) => SharedFileCubit(
                fileId: sharedFileId,
                fileKey: sharedFileKey,
                arweave: context.read<ArweaveService>(),
              ),
              child: SharedFilePage(),
            );
          } else if (showAuthPage) {
            shell = ProfileAuthPage();
          } else {
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
                  shellPage = !state.hasNoDrives
                      ? DriveDetailPage()
                      : Center(
                          child: Text(
                            'You have no personal or attached drives.\nClick the "new" button to add some!',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headline6,
                          ),
                        );
                } else {
                  shellPage = const SizedBox();
                }

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
                        promptToAttachDrive(
                            context: context, initialDriveId: driveId);
                      }
                    },
                    child: AppShell(page: shellPage),
                  ),
                );
              },
            );
          }

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

          if (showAuthPage || isViewingSharedFile) {
            return navigator;
          } else {
            return MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (context) => SyncCubit(
                    profileCubit: context.read<ProfileCubit>(),
                    arweave: context.read<ArweaveService>(),
                    drivesDao: context.read<DrivesDao>(),
                    driveDao: context.read<DriveDao>(),
                    db: context.read<Database>(),
                  ),
                ),
                BlocProvider(
                  create: (context) => DrivesCubit(
                    initialSelectedDriveId: driveId,
                    profileCubit: context.read<ProfileCubit>(),
                    drivesDao: context.read<DrivesDao>(),
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
          }
        },
      );

  @override
  Future<void> setNewRoutePath(AppRoutePath path) async {
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
