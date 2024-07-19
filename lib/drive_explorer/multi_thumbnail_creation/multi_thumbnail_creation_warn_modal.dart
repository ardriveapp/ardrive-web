import 'package:ardrive/drive_explorer/multi_thumbnail_creation/bloc/multi_thumbnail_creation_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MultiThumbnailCreationWarningModal extends StatelessWidget {
  const MultiThumbnailCreationWarningModal({super.key});

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      actions: [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: 'Cancel',
        ),
        ModalAction(
          action: () {
            context
                .read<MultiThumbnailCreationBloc>()
                .add(const CreateMultiThumbnailForAllDrives());
            Navigator.of(context).pop();
          },
          title: 'Continue',
        ),
      ],
      title: 'Create thumbnails',
      description:
          'This will create thumnails for the images stored in all your public and private drives.  You will not be charged!\nThis may take a while',
    );
  }
}
