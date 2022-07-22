import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/io_file.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

class DriveFileDropZone extends StatefulWidget {
  final String driveId;
  final String folderId;

  const DriveFileDropZone({
    Key? key,
    required this.driveId,
    required this.folderId,
  }) : super(key: key);
  @override
  _DriveFileDropZoneState createState() => _DriveFileDropZoneState();
}

class _DriveFileDropZoneState extends State<DriveFileDropZone> {
  late DropzoneViewController controller;
  bool isHovering = false;
  bool isCurrentlyShown = false;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 128, horizontal: 128),
      /* 
            Added padding here so that the drop zone doesn't overlap with the
            Link widget.
            */
      child: IgnorePointer(
        //ignoring: isHovering,
        child: Stack(
          children: [
            if (isHovering) _buildDropZoneOnHover(),
            DropzoneView(
              key: Key('dropZone'),
              onCreated: (ctrl) => controller = ctrl,
              operation: DragOperation.all,
              onDrop: (htmlFile) => _onDrop(
                htmlFile,
                driveId: widget.driveId,
                folderId: widget.folderId,
                context: context,
              ),
              onHover: _onHover,
              onLeave: _onLeave,
              onError: (e) => _onLeave,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDrop(
    htmlFile, {
    required BuildContext context,
    required String driveId,
    required String folderId,
  }) async {
    if (!isCurrentlyShown) {
      isCurrentlyShown = true;
      _onLeave();

      final fileName = await controller.getFilename(htmlFile);
      final fileMIME = await controller.getFileMIME(htmlFile);
      final fileLength = await controller.getFileSize(htmlFile);
      final fileLastModified = await controller.getFileLastModified(htmlFile);

      final htmlUrl = await controller.createFileUrl(htmlFile);
      final fileToUpload = XFile(
        htmlUrl,
        name: fileName,
        mimeType: fileMIME,
        lastModified: fileLastModified,
        length: fileLength,
      );
      final selectedFiles = [await IOFile.fromXFile(fileToUpload, folderId)];
      try {
        //This is the only way to know whether the dropped file is a folder
        await fileToUpload.readAsBytes();
      } catch (e) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(appLocalizationsOf(context).error),
            content: Text(
              appLocalizationsOf(context).errorDragAndDropFolder,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(appLocalizationsOf(context).ok),
              ),
            ],
          ),
          barrierDismissible: true,
        ).then((value) => isCurrentlyShown = false);
        return;
      }
      await showCongestionDependentModalDialog(
        context,
        () => showDialog(
          context: context,
          builder: (_) => BlocProvider<UploadCubit>(
            create: (context) => UploadCubit(
              uploadPlanUtils: UploadPlanUtils(
                arweave: context.read<ArweaveService>(),
                driveDao: context.read<DriveDao>(),
              ),
              driveId: driveId,
              folderId: folderId,
              files: selectedFiles,
              arweave: context.read<ArweaveService>(),
              pst: context.read<PstService>(),
              profileCubit: context.read<ProfileCubit>(),
              driveDao: context.read<DriveDao>(),
            )..startUploadPreparation(),
            child: const UploadForm(),
          ),
          barrierDismissible: false,
        ).then((value) => isCurrentlyShown = false),
      );
    }
  }

  void _onHover() => setState(() => isHovering = true);
  void _onLeave() => setState(() => isHovering = false);
  Widget _buildDropZoneOnHover() => Center(
        child: Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(16),
          width: MediaQuery.of(context).size.width / 2,
          height: MediaQuery.of(context).size.width / 4,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).primaryColor,
            ),
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.upload_file,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
              SizedBox(
                width: 16,
              ),
              Text(
                appLocalizationsOf(context).uploadDragAndDrop,
                style: Theme.of(context).textTheme.headline2,
              ),
            ],
          ),
        ),
      );
}
