import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DrivesHealthCheckModal extends StatefulWidget {
  const DrivesHealthCheckModal({super.key});

  @override
  State<DrivesHealthCheckModal> createState() => _DrivesHealthCheckModalState();
}

class _DrivesHealthCheckModalState extends State<DrivesHealthCheckModal> {
  List<FileEntry> files = [];
  List<FileEntry> allFiles = [];
  List<FileHealthCheckStatus> statuses = [];
  int currentIndex = 0;

  @override
  initState() {
    super.initState();

    final driveDao = context.read<DriveDao>();

    driveDao.select(driveDao.fileEntries).get().then((files) {
      allFiles = files;
      loadFiles(context: context);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (files.isNotEmpty) {
      return SizedBox(
        height: 500,
        width: 400,
        child: ListView.builder(
            itemCount: files.length,
            addAutomaticKeepAlives: true,
            itemBuilder: (context, index) {
              final status = statuses[index];

              return FileHealthCheckTile(
                status: status,
                onFinish: () async {
                  await Future.delayed(const Duration(milliseconds: 500));
                  setState(() {
                    files.add(allFiles[currentIndex]);
                    currentIndex += 1;
                  });
                },
              );
            }),
      );
    }

    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  /// loads all files
  Future<void> loadFiles({
    required BuildContext context,
  }) async {
    if (currentIndex >= allFiles.length) {
      return;
    }

    files.addAll(allFiles.getRange(currentIndex, currentIndex + 10));

    await Future.wait(files.map((file) async {
      await checkHealth(file);
    }));

    await Future.delayed(const Duration(milliseconds: 500));

    currentIndex += 10;

    setState(() {});

    logger.d('Loaded ${allFiles.length} files');

    // ignore: use_build_context_synchronously
    loadFiles(context: context);
  }

  /// checks the health of the file
  Future<void> checkHealth(FileEntry file) async {
    try {
      final arweave = context.read<ArweaveService>();
      final ardriveDownloader = ArDriveDownloader(
          ioFileAdapter: IOFileAdapter(),
          ardriveIo: ArDriveIO(),
          arweave: arweave);
      final dataTxId = file.dataTxId;

      final dataTx = await arweave.getTransactionDetails(file.dataTxId);
      await ardriveDownloader.downloadToMemory(
        dataTx: dataTx!,
        contentType: file.dataContentType!,
        fileName: file.name,
        fileSize: file.size,
        isManifest: false,
        lastModifiedDate: file.lastModifiedDate,
        cipher: dataTx.getTag(EntityTag.cipher),
        cipherIvString: dataTx.getTag(EntityTag.cipherIv),
      );

      statuses.add(FileHealthCheckStatus(
        file: file,
        isSuccess: true,
        isFailed: false,
      ));

      setState(() {});
    } catch (e) {
      statuses.add(FileHealthCheckStatus(
        file: file,
        isSuccess: false,
        isFailed: true,
      ));
    }
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
    if (widget.status.isSuccess) {
      return ListTile(
        title:
            Text(widget.status.file.name, style: typography.paragraphNormal()),
        subtitle: Text(
          'Health check completed',
          style: typography.paragraphNormal(),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.check),
          onPressed: () {},
        ),
      );
    }

    if (widget.status.isFailed) {
      return ListTile(
        title:
            Text(widget.status.file.name, style: typography.paragraphNormal()),
        subtitle: Text(
          'Health check failed',
          style: typography.paragraphNormal(),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
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
        style: typography.paragraphNormal(),
      ),
    );
  }
}
