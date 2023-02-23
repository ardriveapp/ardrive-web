import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
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
  DriveFileDropZoneState createState() => DriveFileDropZoneState();
}

class DriveFileDropZoneState extends State<DriveFileDropZone> {
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
              key: const Key('dropZone'),
              onCreated: (ctrl) => controller = ctrl,
              operation: DragOperation.all,
              onDrop: (htmlFile) => _onDrop(
                htmlFile,
                driveId: widget.driveId,
                parentFolderId: widget.folderId,
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
    required String parentFolderId,
  }) async {
    if (!isCurrentlyShown) {
      isCurrentlyShown = true;
      _onLeave();
      final selectedFiles = <UploadFile>[];
      try {
        final htmlUrl = await controller.createFileUrl(htmlFile);

        // We use xFile to get the bytes and also validate if it is a file
        final bytes = await XFile(htmlUrl).readAsBytes();
        final ioFile = await IOFile.fromData(bytes,
            name: await controller.getFilename(htmlFile),
            lastModifiedDate: await controller.getFileLastModified(htmlFile));

        selectedFiles.add(UploadFile(
          ioFile: ioFile,
          parentFolderId: parentFolderId,
        ));
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

      // ignore: use_build_context_synchronously
      await showCongestionDependentModalDialog(
        context,
        () => showDialog(
          context: context,
          builder: (_) => BlocProvider<UploadCubit>(
            create: (context) => UploadCubit(
              uploadPlanUtils: UploadPlanUtils(
                arweave: context.read<ArweaveService>(),
                turboService: context.read<TurboService>(),
                driveDao: context.read<DriveDao>(),
              ),
              driveId: driveId,
              parentFolderId: parentFolderId,
              files: selectedFiles,
              arweave: context.read<ArweaveService>(),
              turbo: context.read<TurboService>(),
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
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
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
              const SizedBox(
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
