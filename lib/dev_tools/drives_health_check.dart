import 'dart:async';

import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class DrivesHealthCheckModal extends StatefulWidget {
  const DrivesHealthCheckModal({super.key});

  @override
  State<DrivesHealthCheckModal> createState() => _DrivesHealthCheckModalState();
}

class _DrivesHealthCheckModalState extends State<DrivesHealthCheckModal> {
  List<FileHealthCheckStatus> statuses = [];
  List<DriveHealthCheckStatus> driveStatuses = [];
  List<Drive> drives = [];
  int numberOfFiles = 0;

  @override
  initState() {
    super.initState();

    final driveDao = context.read<DriveDao>();

    driveDao.select(driveDao.drives).get().then((drives) {
      setState(() {
        this.drives = drives;
      });

      processDrivesSequentially();
    });
  }

  Future<void> processDrivesSequentially() async {
    final driveDao = context.read<DriveDao>();

    for (final drive in drives) {
      final status = DriveHealthCheckStatus(
        drive: drive,
        files: [],
        totalFiles: 0,
      );

      driveStatuses.add(status);
    }

    setState(() {});

    for (final currentStatus in driveStatuses) {
      final files = await (driveDao.select(driveDao.fileEntries)
            ..where((tbl) => tbl.driveId.equals(currentStatus.drive.id)))
          .get();
      if (files.isEmpty) {
        currentStatus.isLoading = false;

        setState(() {});

        continue;
      }

      currentStatus.totalFiles = files.length;

      selectedDriveStatus = currentStatus;

      setState(() {});

      await processFiles(files, currentStatus);

      currentStatus.isLoading = false;

      setState(() {});
    }
  }

  late DriveHealthCheckStatus selectedDriveStatus;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    if (driveStatuses.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SizedBox(
      child: ArDriveModalNew(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: MediaQuery.of(context).size.width * 0.8,
          minHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        content: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Drives',
                            style: typography.heading4(
                              fontWeight: ArFontWeight.bold,
                            )),
                        Text('Click on a drive to view details',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                            )),
                        const SizedBox(
                          height: 8,
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.72,
                          child: ListView.separated(
                              itemCount: driveStatuses.length,
                              addAutomaticKeepAlives: true,
                              separatorBuilder: (context, index) =>
                                  const Divider(),
                              shrinkWrap: true,
                              itemBuilder: (context, index) {
                                final driveStatus = driveStatuses[index];

                                return ArDriveClickArea(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        selectedDriveStatus = driveStatus;
                                      });
                                    },
                                    child: DriveHealthCheckTile(
                                      status: driveStatus,
                                      key: Key(driveStatus.drive.id),
                                      isSelected:
                                          selectedDriveStatus.drive.id ==
                                              driveStatus.drive.id,
                                    ),
                                  ),
                                );
                              }),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Flexible(
                  flex: 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        height: 8,
                      ),
                      Text(
                        'Selected Drive: ${selectedDriveStatus.drive.name}',
                        style: typography.paragraphLarge(
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                      Text('Success Files - ${selectedDriveStatus.drive.name}',
                          style: typography.paragraphLarge()),
                      const SizedBox(
                        height: 8,
                      ),
                      Flexible(
                        flex: 1,
                        child: ArDriveCard(
                          content: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.32,
                            ),
                            child: Builder(builder: (context) {
                              final successFiles = selectedDriveStatus.files
                                  .where((element) => element.isSuccess)
                                  .toList();
                              if (successFiles.isEmpty) {
                                return const Center(
                                  child: Text('No files found'),
                                );
                              }

                              return ListView.builder(
                                  itemCount: successFiles.length,
                                  addAutomaticKeepAlives: true,
                                  shrinkWrap: true,
                                  itemBuilder: (context, index) {
                                    final status = successFiles[index];

                                    return FileHealthCheckTile(
                                      status: status,
                                      onFinish: () async {},
                                    );
                                  });
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      Text('Failed Files - ${selectedDriveStatus.drive.name}',
                          style: typography.paragraphLarge()),
                      const SizedBox(
                        height: 8,
                      ),
                      Flexible(
                        flex: 1,
                        child: ArDriveCard(
                          content: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.32,
                            ),
                            child: Builder(builder: (context) {
                              final failedFiles = selectedDriveStatus.files
                                  .where((element) => element.isFailed)
                                  .toList();
                              if (failedFiles.isEmpty) {
                                return const Center(
                                  child: Text('No files found'),
                                );
                              }
                              return ListView.builder(
                                  itemCount: failedFiles.length,
                                  addAutomaticKeepAlives: true,
                                  shrinkWrap: true,
                                  itemBuilder: (context, index) {
                                    final status = failedFiles[index];

                                    return FileHealthCheckTile(
                                      status: status,
                                      onFinish: () async {},
                                    );
                                  });
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Drives Loaded: ${driveStatuses.where((element) => !element.isLoading).length} of ${driveStatuses.length}',
              style: typography.paragraphLarge(
                fontWeight: ArFontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> processFiles(
      List<FileEntry> files, DriveHealthCheckStatus driveStatus) async {
    const int maxConcurrentTasks = 20;
    final StreamController<void> controller = StreamController<void>();

    // Function to process files
    void processNext() {
      if (files.isNotEmpty) {
        final file = files.removeAt(0);
        checkHealth(file, driveStatus).then((_) {
          if (files.isEmpty) {
            controller.close();
            return;
          }

          controller.add(null);
          setState(() {});
        });
      }
    }

    // Start initial batch of downloads
    for (int i = 0; i < maxConcurrentTasks && files.isNotEmpty; i++) {
      processNext();
      setState(() {});
    }

    // Listen for completion events and process next file
    await for (final _ in controller.stream) {
      processNext();
      setState(() {});
    }
  }

  /// checks the health of the file
  Future<void> checkHealth(
      FileEntry file, DriveHealthCheckStatus driveStatus) async {
    try {
      final arweave = context.read<ArweaveService>();

      final url =
          '${arweave.client.api.gatewayUrl.origin}/raw/${file.dataTxId}';

      final response = await http.head(Uri.parse(url));

      logger.d(
          'Checking health of ${file.name}. Response: ${response.statusCode}');

      if (response.statusCode > 400) {
        driveStatus.files.add(FileHealthCheckStatus(
          file: file,
          isSuccess: false,
          isFailed: true,
        ));
        setState(() {});
        return;
      }

      driveStatus.files.add(FileHealthCheckStatus(
        file: file,
        isSuccess: true,
        isFailed: false,
      ));

      setState(() {});
    } catch (e) {
      driveStatus.files.add(FileHealthCheckStatus(
        file: file,
        isSuccess: false,
        isFailed: true,
      ));
    }
  }
}

class DriveHealthCheckTile extends StatefulWidget {
  const DriveHealthCheckTile(
      {super.key, required this.status, this.isSelected = false});

  final DriveHealthCheckStatus status;
  final bool isSelected;

  @override
  State<DriveHealthCheckTile> createState() => _DriveHealthCheckTielState();
}

class _DriveHealthCheckTielState extends State<DriveHealthCheckTile> {
  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final failedFiles =
        widget.status.files.where((element) => element.isFailed).toList();
    final progress = widget.status.totalFiles == 0 && widget.status.isLoading
        ? 0.0
        : widget.status.totalFiles == 0 && !widget.status.isLoading
            ? 1.0
            : widget.status.files.length / widget.status.totalFiles;
    return ArDriveCard(
      content: Column(
        children: [
          Row(
            children: [
              Text(
                widget.status.drive.name,
                style: ArDriveTypographyNew.of(context).paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: failedFiles.isNotEmpty ? colorTokens.strokeRed : null,
                ),
              ),
              const Spacer(),
              if (failedFiles.isNotEmpty) ...[
                ArDriveIcons.triangle(size: 20, color: colorTokens.strokeRed),
                const SizedBox(width: 2),
                Text(failedFiles.length.toString(),
                    style: ArDriveTypographyNew.of(context).paragraphLarge(
                      fontWeight: ArFontWeight.bold,
                      color: colorTokens.strokeRed,
                    )),
                const SizedBox(width: 8),
              ],
              Text(
                '${widget.status.files.length}/${widget.status.totalFiles}',
                style: ArDriveTypographyNew.of(context).paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          ArDriveProgressBar(
            percentage: progress,
            indicatorColor: progress == 1
                ? failedFiles.isNotEmpty
                    ? colorTokens.strokeRed
                    : ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeSuccessDefault
                : colorTokens.textHigh,
            backgroundColor: colorTokens.textLow,
          ),
        ],
      ),
    );
  }
}

class DriveHealthCheckStatus {
  final Drive drive;
  final List<FileHealthCheckStatus> files;
  int totalFiles;
  bool isLoading;

  DriveHealthCheckStatus({
    required this.drive,
    required this.files,
    required this.totalFiles,
    this.isLoading = true,
  });
}

class FileHealthCheckStatus {
  final FileEntry file;
  final bool isSuccess;
  final bool isFailed;

  FileHealthCheckStatus({
    required this.file,
    required this.isSuccess,
    required this.isFailed,
  });
}

class FileHealthCheckTile extends StatefulWidget {
  const FileHealthCheckTile(
      {super.key, required this.status, required this.onFinish});

  final Function onFinish;
  final FileHealthCheckStatus status;

  @override
  State<FileHealthCheckTile> createState() => _FileHealthCheckTileState();
}

class _FileHealthCheckTileState extends State<FileHealthCheckTile> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    if (widget.status.isSuccess) {
      return ListTile(
        title: Text(widget.status.file.name,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.bold,
              color: colorTokens.textHigh,
            )),
        subtitle: Text(
          'Health check completed',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textMid,
          ),
        ),
        trailing: IconButton(
          color: colorTokens.textHigh,
          icon: const Icon(
            Icons.check,
          ),
          onPressed: () {},
        ),
      );
    }

    if (widget.status.isFailed) {
      return ListTile(
        title: Text(
          widget.status.file.name,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.bold,
            color: colorTokens.textHigh,
          ),
        ),
        subtitle: Text(
          'Health check failed',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textLow,
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.close,
            color: colorTokens.textHigh,
          ),
          onPressed: () {
            widget.onFinish();
          },
        ),
      );
    }

    return ListTile(
      title: Text(widget.status.file.name, style: typography.paragraphNormal()),
      subtitle: Text(
        'Checking health of ${widget.status.file.name}',
        style: typography.paragraphNormal(
          fontWeight: ArFontWeight.bold,
          color: colorTokens.buttonDisabled,
        ),
      ),
    );
  }
}
