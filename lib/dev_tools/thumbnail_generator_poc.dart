// ignore_for_file: use_build_context_synchronously

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThumbnailGeneratorPOC extends StatefulWidget {
  const ThumbnailGeneratorPOC({super.key});

  @override
  State<ThumbnailGeneratorPOC> createState() => _ThumbnailGeneratorPOCState();
}

class _ThumbnailGeneratorPOCState extends State<ThumbnailGeneratorPOC> {
  List<FileEntry>? _files;
  final Map<String, bool> _thumbnailsGenerated = {};

  // load files
  Future<void> _generateThumbnailsForFiles({required String driveId}) async {
    final driveDao = context.read<DriveDao>();

    final files = await (driveDao.select(driveDao.fileEntries)
          ..where((tbl) => tbl.driveId.equals(driveId)))
        .get();

    setState(() {
      _files = files;
    });
    final arweaveService = context.read<ArweaveService>();
    final turboUploadService = context.read<TurboUploadService>();
    final wallet = context.read<ArDriveAuth>().currentUser.wallet;
    final downloader = ArDriveDownloader(
      ardriveIo: ArDriveIO(),
      arweave: arweaveService,
      ioFileAdapter: IOFileAdapter(),
    );

    for (var f in files) {
      if (FileTypeHelper.isImage(f.dataContentType ?? '') == false) {
        logger.i('Skipping file');
        continue;
      }

      final dataTx = await arweaveService.getTransactionDetails(f.dataTxId);

      SecretKey? fileKey;

      final drive = await driveDao.driveById(driveId: driveId).getSingle();

      if (drive.isPrivate) {
        final driveKey = await driveDao.getDriveKey(
          drive.id,
          context.read<ArDriveAuth>().currentUser.cipherKey,
        );

        fileKey = await ArDriveCrypto().deriveFileKey(
          driveKey!,
          f.id,
        );
      }

      final bytes = await downloader.downloadToMemory(
        dataTx: dataTx!,
        fileSize: f.size,
        fileName: f.name,
        lastModifiedDate: f.lastModifiedDate,
        contentType: f.dataContentType!,
        isManifest: false,
        fileKey: fileKey,
      );

      final uploader = ArDriveUploader(
          turboUploadUri: Uri.parse(
              context.read<ConfigService>().config.defaultTurboUploadUrl!));

      final data = await generateThumbnail(bytes, ThumbnailSize.small);

      final file = await IOFileAdapter().fromData(
        data.thumbnail,
        name: 'thumbnail',
        lastModifiedDate: DateTime.now(),
      );

      final thumbnailArgs = ThumbnailUploadMetadata(
        contentType: 'image/png',
        height: data.height,
        width: data.width,
        size: data.thumbnail.length,
        relatesTo: f.dataTxId,
        aspectRatio: data.aspectRatio,
        name: data.name,
        originalFileId: f.id,
      );

      final controller = await uploader.uploadThumbnail(
        thumbnailMetadata: thumbnailArgs,
        file: file,
        type: UploadType.turbo,
        wallet: context.read<ArDriveAuth>().currentUser.wallet,
        fileKey: fileKey,
      );

      controller.onDone((tasks) async {
        logger.i('Thumbnail uploaded');

        setState(() {
          _thumbnailsGenerated[f.dataTxId] = true;
        });

        await driveDao.transaction(() async {
          f = f.copyWith(
            lastUpdated: DateTime.now(),
            thumbnail: drift.Value(
              (tasks.first as ThumbnailUploadTask).metadata.toJson().toString(),
            ),
          );

          final fileEntity = f.asEntity();

          if (turboUploadService.useTurboUpload) {
            final fileDataItem = await arweaveService.prepareEntityDataItem(
              fileEntity,
              wallet,
              // key: fileKey,
            );

            await turboUploadService.postDataItem(
              dataItem: fileDataItem,
              wallet: wallet,
            );
            fileEntity.txId = fileDataItem.id;
          } else {}

          logger.i(
              'Updating file ${f.id} with txId ${fileEntity.txId}. Data content type: ${fileEntity.dataContentType}');

          await driveDao.writeToFile(f);

          await driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
              performedAction: RevisionAction.rename));
        });
      });
    }
  }

  final textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    if (_files == null) {
      return Center(
        child: Column(
          children: [
            ArDriveTextFieldNew(
              controller: textController,
            ),
            ElevatedButton(
              onPressed: () =>
                  _generateThumbnailsForFiles(driveId: textController.text),
              child: const Text('Generate Thumbnails'),
            ),
          ],
        ),
      );
    } else {
      return ListView.builder(
        itemCount: _files!.length,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          final file = _files![index];
          return ListTile(
            title: Text(file.name),
            subtitle: Text(file.dataTxId),
            trailing: _thumbnailsGenerated[file.dataTxId] == true
                ? const Icon(Icons.check)
                : const Icon(Icons.close),
          );
        },
      );
    }
  }
}
