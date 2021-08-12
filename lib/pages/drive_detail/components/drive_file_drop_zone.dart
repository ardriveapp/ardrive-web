import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:moor/moor.dart';

class DriveFileDropZone extends StatefulWidget {
  @override
  _DriveFileDropZoneState createState() => _DriveFileDropZoneState();
}

class _DriveFileDropZoneState extends State<DriveFileDropZone> {
  late DropzoneViewController controller;
  bool isHovering = false;
  bool isCurrentlyShown = false;
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
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
                      driveId: state.currentDrive!.id,
                      folderId: state.currentFolder!.folder!.id,
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

        return const SizedBox();
      },
    );
  }

  Future<void> _onDrop(
    htmlFile, {
    BuildContext? context,
    required String? driveId,
    required String? folderId,
  }) async {
    if (!isCurrentlyShown) {
      isCurrentlyShown = true;
      _onLeave();

      final fileName = await controller.getFilename(htmlFile);
      final fileMIME = await controller.getFileMIME(htmlFile);
      final fileLength = await controller.getFileSize(htmlFile);
      final htmlUrl = await controller.createFileUrl(htmlFile);
      final fileToUpload = XFile(
        htmlUrl,
        name: fileName,
        mimeType: fileMIME,
        lastModified: DateTime.now(),
        length: fileLength,
      );
      final selectedFiles = <XFile>[fileToUpload];

      await showDialog(
        context: context!,
        builder: (_) => BlocProvider<UploadCubit>(
          create: (context) => UploadCubit(
            driveId: driveId,
            folderId: folderId,
            files: selectedFiles,
            arweave: context.read<ArweaveService>(),
            pst: context.read<PstService>(),
            profileCubit: context.read<ProfileCubit>(),
            driveDao: context.read<DriveDao>(),
          ),
          child: UploadForm(),
        ),
        barrierDismissible: false,
      ).then((value) => isCurrentlyShown = false);
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
                'Upload File',
                style: Theme.of(context).textTheme.headline2,
              ),
            ],
          ),
        ),
      );
}
