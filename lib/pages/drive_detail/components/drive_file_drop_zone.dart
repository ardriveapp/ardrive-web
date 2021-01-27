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
  DropzoneViewController controller;
  var isHovering = false;
  @override
  Widget build(BuildContext context) {
    final driveDetailBloc = context.watch<DriveDetailCubit>();
    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          return Stack(
            children: [
              if (isHovering) _builDropZoneOnHover(),
              DropzoneView(
                onCreated: (ctrl) => controller = ctrl,
                operation: DragOperation.all,
                onDrop: (htmlFile) => _onDrop(
                  htmlFile,
                  driveId: state.currentDrive.id,
                  folderId: state.currentFolder.folder.id,
                  context: context,
                ),
                onHover: _onHover,
                onLeave: _onLeave,
                onError: (e) => _onLeave,
              ),
            ],
          );
        }

        return const SizedBox();
      },
    );
  }

  Future<void> _onDrop(
    htmlFile, {
    BuildContext context,
    @required String driveId,
    @required String folderId,
  }) async {
    _onLeave();

    final fileData = await controller.getFileData(htmlFile);
    final fileName = await controller.getFilename(htmlFile);
    final fileMIME = await controller.getFileMIME(htmlFile);
    final fileLength = await controller.getFileSize(htmlFile);

    final fileToUpload = XFile.fromData(
      fileData,
      name: fileName,
      mimeType: fileMIME,
      lastModified: DateTime.now(),
      path: '/',
      length: fileLength,
    );
    final selectedFiles = <XFile>[fileToUpload];

    await showDialog(
      context: context,
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
    );
  }

  void _onHover() => setState(() => isHovering = true);
  void _onLeave() => setState(() => isHovering = false);
  Widget _builDropZoneOnHover() => Placeholder();
}
