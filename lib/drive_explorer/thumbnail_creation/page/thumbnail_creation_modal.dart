import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail_creation/bloc/thumbnail_creation_bloc.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThumbnailCreationModal extends StatelessWidget {
  const ThumbnailCreationModal({super.key, required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => ThumbnailRepository(
        arDriveAuth: context.read<ArDriveAuth>(),
        arDriveDownloader: context.read<ArDriveDownloader>(),
        arDriveUploader: context.read<ArDriveUploader>(),
        arweaveService: context.read<ArweaveService>(),
        driveDao: context.read<DriveDao>(),
        turboUploadService: context.read<TurboUploadService>(),
      ),
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
              // explain what is a thumbnail
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
            title: 'Confirm'),
      ],
    );
  }
}
