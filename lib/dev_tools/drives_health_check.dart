import 'dart:async';

import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// http
import 'package:http/http.dart' as http;

class DrivesHealthCheckModal extends StatefulWidget {
  const DrivesHealthCheckModal({super.key});

  @override
  State<DrivesHealthCheckModal> createState() => _DrivesHealthCheckModalState();
}

class _DrivesHealthCheckModalState extends State<DrivesHealthCheckModal> {
  List<FileHealthCheckStatus> statuses = [];
  int numberOfFiles = 0;

  @override
  initState() {
    super.initState();

    final driveDao = context.read<DriveDao>();

    driveDao.select(driveDao.fileEntries).get().then((files) {
      numberOfFiles = files.length;
      processFiles(files);
    });
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    if (statuses.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 500,
            child: ListView.builder(
                itemCount: statuses.length,
                addAutomaticKeepAlives: true,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  final status = statuses[index];

                  return FileHealthCheckTile(
                    status: status,
                    onFinish: () async {},
                  );
                }),
          ),
          const SizedBox(height: 20),
          Text(
            'Files Processed: ${statuses.length}',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.bold,
            ),
          ),
          Text(
            'Files Remaining: ${numberOfFiles - statuses.length}',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.bold,
            ),
          ),
          const Divider(
            height: 20,
          ),
          Text(
            'Failed Files: ${statuses.where((status) => status.isFailed).length}',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.bold,
            ),
          ),
          Text(
            'Success Files: ${statuses.where((status) => status.isSuccess).length}',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.bold,
            ),
          ),
          ArDriveProgressBar(percentage: statuses.length / numberOfFiles),
          if (statuses.length == numberOfFiles)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ArDriveButton(
                    text: 'Close',
                    onPressed: () => Navigator.of(context).pop()),
              ),
            ),
        ],
      );
    }

    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Future<void> processFiles(List<FileEntry> files) async {
    const int maxConcurrentTasks = 20;
    final StreamController<void> controller = StreamController<void>();

    // Function to process files
    void processNext() {
      if (files.isNotEmpty) {
        final file = files.removeAt(0);
        checkHealth(file).then((_) {
          controller.add(null);
          setState(() {});
        });
      } else {
        controller.close();
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
  Future<void> checkHealth(FileEntry file) async {
    try {
      final arweave = context.read<ArweaveService>();

      final url =
          '${arweave.client.api.gatewayUrl.origin}/raw/${file.dataTxId}';

      final response = await http.head(Uri.parse(url));

      logger.d(
          'Checking health of ${file.name}. Response: ${response.statusCode}');

      if (response.statusCode > 400) {
        statuses.add(FileHealthCheckStatus(
          file: file,
          isSuccess: false,
          isFailed: true,
        ));
        setState(() {});
        return;
      }

      statuses.add(FileHealthCheckStatus(
        file: file,
        isSuccess: true,
        isFailed: false,
      ));

      setState(() {});
    } catch (e) {}
  }
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
