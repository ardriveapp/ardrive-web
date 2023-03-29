// GoRouter configuration
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/drives/:driveId',
      builder: (context, state) {
        final driveId = state.params['driveId']!;
        return MultiBlocProvider(
          providers: [
            BlocProvider<SyncCubit>(
              create: (context) => SyncCubit(
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
                initialSelectedDriveId: driveId,
                profileCubit: context.read<ProfileCubit>(),
                driveDao: context.read<DriveDao>(),
              ),
            ),
            BlocProvider<DriveDetailCubit>(
              key: ValueKey(state.params['driveId']!),
              create: (context) => DriveDetailCubit(
                driveId: state.params['driveId']!,
                // initialFolderId: state.params['driveId'],
                profileCubit: context.read<ProfileCubit>(),
                driveDao: context.read<DriveDao>(),
                config: context.read<AppConfig>(),
              ),
            ),
          ],
          child: const Material(
            child: DriveExplorer(),
          ),
        );
      },
    )
  ],
);

class DriveExplorer extends StatelessWidget {
  const DriveExplorer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesCubit, DrivesState>(
      builder: (context, state) {
        if (state is DrivesLoadSuccess) {
          print(state.userDrives.length);
          return !state.hasNoDrives
              ? DriveDetailPage(
                  driveId: state.selectedDriveId,
                )
              : const NoDrivesPage();
        }

        return BlocBuilder<SyncCubit, SyncState>(
                builder: (context, syncState) => syncState is SyncInProgress
                    ? Stack(
                        children: [
                          
                          SizedBox.expand(
                            child: Container(
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                          BlocBuilder<ProfileCubit, ProfileState>(
                            builder: (context, state) {
                              return FutureBuilder(
                                future: context
                                    .read<ProfileCubit>()
                                    .isCurrentProfileArConnect(),
                                builder: (BuildContext context,
                                    AsyncSnapshot snapshot) {
                                  return Align(
                                    alignment: Alignment.center,
                                    child: Material(
                                      child: ProgressDialog(
                                          progressBar: ProgressBar(
                                            percentage: context
                                                .read<SyncCubit>()
                                                .syncProgressController
                                                .stream,
                                          ),
                                          // percentageDetails: _syncStreamBuilder(
                                          //     builderWithData: (syncProgress) =>
                                          //         Text(appLocalizationsOf(
                                          //                 context)
                                          //             .syncProgressPercentage(
                                          //                 (syncProgress
                                          //                             .progress *
                                          //                         100)
                                          //                     .roundToDouble()
                                          //                     .toString()))),
                                          // progressDescription:
                                          //     _syncStreamBuilder(
                                          //   builderWithData: (syncProgress) =>
                                          //       Text(
                                          //     syncProgress.drivesCount == 0
                                          //         ? ''
                                          //         : syncProgress.drivesCount > 1
                                          //             ? appLocalizationsOf(
                                          //                     context)
                                          //                 .driveSyncedOfDrivesCount(
                                          //                     syncProgress
                                          //                         .drivesSynced,
                                          //                     syncProgress
                                          //                         .drivesCount)
                                          //             : appLocalizationsOf(
                                          //                     context)
                                          //                 .syncingOnlyOneDrive,
                                          //     style: const TextStyle(
                                          //         fontSize: 16,
                                          //         fontWeight: FontWeight.bold),
                                          //   ),
                                          // ),
                                          title: snapshot.data ?? false
                                              ? appLocalizationsOf(context)
                                                  .syncingPleaseRemainOnThisTab
                                              : appLocalizationsOf(context)
                                                  .syncingPleaseWait),
                                    ),
                                  );
                                },
                              );
                            },

        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
