import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/file_download/html_dart.dart';
import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pedantic/pedantic.dart';

import 'components.dart';

late OverlayEntry entry;

showDownloadOverlay({
  required BuildContext context,
  required DriveID driveId,
  required FileID fileId,
  required TxID dataTxId,
}) {
  print('showDownloadOverlay');
  entry = OverlayEntry(
    builder: (context) => Positioned(
      right: 20,
      bottom: 20,
      child: BlocProvider<FileDownloadCubit>(
        create: (_) => ProfileFileDownloadCubit(
          driveId: driveId,
          fileId: fileId,
          dataTxId: dataTxId,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: Material(child: FileDownloadFloating()),
      ),
    ),
  );

  Overlay.of(context)!.insert(entry);
}

Future<void> promptToDownloadProfileFile({
  required BuildContext context,
  required DriveID driveId,
  required FileID fileId,
  required TxID dataTxId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => ProfileFileDownloadCubit(
          driveId: driveId,
          fileId: fileId,
          dataTxId: dataTxId,
          profileCubit: context.read<ProfileCubit>(),
          driveDao: context.read<DriveDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: FileDownloadDialog(),
      ),
    );

Future<void> promptToDownloadSharedFile({
  required BuildContext context,
  required String fileId,
  SecretKey? fileKey,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider<FileDownloadCubit>(
        create: (_) => SharedFileDownloadCubit(
          fileId: fileId,
          fileKey: fileKey,
          arweave: context.read<ArweaveService>(),
        ),
        child: FileDownloadDialog(),
      ),
    );

class FileDownloadFloating extends StatelessWidget {
  const FileDownloadFloating({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FileDownloadCubit, FileDownloadState>(
      listener: (context, state) async {
        if (state is FileDownloadSuccess) {
          entry.remove();
          final savePath = await getSavePath();
          if (savePath != null) {
            unawaited(state.file.saveTo(savePath));
          }

          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        if (state is FileDownloadInProgress) {
          return SizedBox(
            width: 300,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ProgressBar(
                      percentage: downloadStream,
                      darkMode: true,
                    ),
                    StreamBuilder<DownloadProgress>(
                      stream: downloadStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final speed =
                              snapshot.data!.speed!.toStringAsFixed(2);
                          String timeFormatter(int time) {
                            Duration duration = Duration(seconds: time.round());

                            return [
                              if (duration.inMinutes > 60) duration.inHours,
                              if (duration.inSeconds > 60) duration.inMinutes,
                              duration.inSeconds
                            ]
                                .map((seg) => seg
                                    .remainder(60)
                                    .toString()
                                    .padLeft(2, '0'))
                                .join(':');
                          }

                          final remainingTime = snapshot.data!.remainingTime;

                          return Text(
                            'Download speed: $speed MB/s Remaining time: ${timeFormatter(remainingTime!)}s',
                            style: TextStyle(color: Colors.white),
                          );
                        }
                        return Container();
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const SizedBox(
          height: 300,
          width: 300,
        );
      },
    );
  }
}

class FileDownloadDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FileDownloadCubit, FileDownloadState>(
        listener: (context, state) async {
          if (state is FileDownloadSuccess) {
            final savePath = await getSavePath();
            if (savePath != null) {
              unawaited(state.file.saveTo(savePath));
            }

            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          if (state is FileDownloadStarting) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).downloadingFile,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Center(child: CircularProgressIndicator()),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appLocalizationsOf(context).cancel),
                ),
              ],
            );
          } else if (state is FileDownloadInProgress) {
            return ProgressDialog(
              title: 'Downloading',
              progressBar: ProgressBar(percentage: downloadStream),
              progressDescription: StreamBuilder<DownloadProgress>(
                stream: downloadStream,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final speed = snapshot.data!.speed!.toStringAsFixed(2);
                    String timeFormatter(int time) {
                      Duration duration = Duration(seconds: time.round());

                      return [
                        if (duration.inMinutes > 60) duration.inHours,
                        if (duration.inSeconds > 60) duration.inMinutes,
                        duration.inSeconds
                      ]
                          .map((seg) =>
                              seg.remainder(60).toString().padLeft(2, '0'))
                          .join(':');
                    }

                    final remainingTime = snapshot.data!.remainingTime;

                    return Text(
                        'Download speed: $speed MB/s Remaining time: ${timeFormatter(remainingTime!)}s');
                  }
                  return Container();
                },
              ),
              percentageDetails: StreamBuilder<DownloadProgress>(
                  stream: downloadStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final percentageTxt = appLocalizationsOf(context)
                          .syncProgressPercentage(
                              (snapshot.data!.progress * 100)
                                  .roundToDouble()
                                  .toString());

                      return Text(percentageTxt);
                    }
                    return Container();
                  }),
            );
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).downloadingFile,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    state.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(filesize(state.totalByteCount)),
                  trailing: const CircularProgressIndicator(),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    context.read<FileDownloadCubit>().abortDownload();
                    Navigator.pop(context);
                  },
                  child: Text(appLocalizationsOf(context).cancel),
                ),
              ],
            );
          } else if (state is FileDownloadFailure) {
            return AppDialog(
              dismissable: false,
              title: appLocalizationsOf(context).fileFailedToDownload,
              content: SizedBox(
                width: kMediumDialogWidth,
                child:
                    Text(appLocalizationsOf(context).tryAgainDownloadingFile),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appLocalizationsOf(context).ok),
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        },
      );
}
