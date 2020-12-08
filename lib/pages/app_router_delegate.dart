import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_shell.dart';

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  String driveId;
  String driveFolderId;

  String sharedFileId;

  bool get isViewingSharedFile => sharedFileId != null;

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(
        driveId: driveId,
        driveFolderId: driveFolderId,
        sharedFileId: sharedFileId,
      );

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  AppRouterDelegate() : navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          Widget shell;
          if (isViewingSharedFile) {
            shell = BlocProvider<SharedFileCubit>(
              key: ValueKey(sharedFileId),
              create: (_) => SharedFileCubit(
                fileId: sharedFileId,
                arweave: context.read<ArweaveService>(),
              ),
              child: SharedFilePage(),
            );
          } else if (state is! ProfileLoaded) {
            shell = ProfileAuthPage();
          } else {
            shell = BlocConsumer<DrivesCubit, DrivesState>(
              listener: (context, state) {
                if (state is DrivesLoadSuccess) {
                  navigateToDriveDetailPage(state.selectedDriveId);
                }
              },
              builder: (context, state) {
                Widget shellPage;
                if (state is DrivesLoadSuccess) {
                  if (state.hasNoDrives) {
                    shellPage = Center(
                      child: Text(
                        'You have no personal or attached drives.\nClick the "new" button to add some!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headline6,
                      ),
                    );
                  } else {
                    shellPage = DriveDetailPage(driveId: state.selectedDriveId);
                  }
                } else {
                  shellPage = Container();
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
                  child: AppShell(page: shellPage),
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

          if (state is! ProfileLoaded || isViewingSharedFile) {
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
  }

  void navigateToDriveDetailPage(String driveId, [String driveFolderId]) {
    // Only update the drive folder id to null if the drive id is changing.
    if ((driveFolderId == null && this.driveId != driveId) ||
        driveFolderId != null) {
      this.driveFolderId = driveFolderId;
    }

    this.driveId = driveId;

    notifyListeners();
  }
}

extension RouterExtensions on Router {
  AppRouterDelegate get delegate => routerDelegate as AppRouterDelegate;
}
