import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail_creation/bloc/thumbnail_creation_bloc.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThumbnailCreationModal extends StatelessWidget {
  const ThumbnailCreationModal({super.key, required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => context.read<ThumbnailRepository>(),
      child: BlocProvider(
        create: (context) {
          return ThumbnailCreationBloc(
              thumbnailRepository: context.read<ThumbnailRepository>());
        },
        child: _ThumbnailCreationModal(
          fileDataTableItem: fileDataTableItem,
        ),
      ),
    );
  }
}

class _ThumbnailCreationModal extends StatelessWidget {
  const _ThumbnailCreationModal({required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: 'Create Thumbnail',
      content: BlocConsumer<ThumbnailCreationBloc, ThumbnailCreationState>(
        listener: (context, state) {
          if (state is ThumbnailCreationSuccess) {
            context.read<DriveDetailCubit>().refreshDriveDataTable();
            Navigator.of(context).pop();
          }
        },
        builder: (context, state) {
          if (state is ThumbnailCreationLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ThumbnailCreationError) {
            return const Text(
                'An error occurred while creating the thumbnail.');
          } else if (state is ThumbnailCreationSuccess) {
            return const Text('Thumbnail created successfully.');
          }

          return const Column(
            children: [
              Text(
                'A thumbnail is a small image that represents your file. '
                'It will be displayed in the file explorer and in the file details view.',
              ),
            ],
          );
        },
      ),
      actions: [
        ModalAction(
            action: () {
              Navigator.of(context).pop();
            },
            title: 'Cancel'),
        ModalAction(
          isEnable: context.watch<ThumbnailCreationBloc>().state
              is! ThumbnailCreationLoading,
          action: () {
            context.read<ThumbnailCreationBloc>().add(
                  CreateThumbnail(
                    fileDataTableItem: fileDataTableItem,
                  ),
                );
          },
          title: 'Confirm',
        ),
      ],
    );
  }
}
