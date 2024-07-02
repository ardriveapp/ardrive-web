import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/drive_explorer/multi_thumbnail_creation/bloc/multi_thumbnail_creation_bloc.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MultiThumbnailCreationModal extends StatelessWidget {
  const MultiThumbnailCreationModal({required this.drive, super.key});

  final Drive drive;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MultiThumbnailCreationBloc(
          driveRepository: DriveRepository(
            driveDao: context.read<DriveDao>(),
          ),
          thumbnailRepository: context.read<ThumbnailRepository>())
        ..add(CreateMultiThumbnailForDrive(drive: drive)),
      child: MultiThumbnailCreationModalContent(
        drive: drive,
      ),
    );
  }
}

class MultiThumbnailCreationModalContent extends StatelessWidget {
  const MultiThumbnailCreationModalContent({required this.drive, super.key});

  final Drive drive;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MultiThumbnailCreationBloc,
        MultiThumbnailCreationState>(
          
      listener: (context, state) {
        if (state is MultiThumbnailCreationThumbnailsLoaded) {
          Navigator.of(context).pop();
        }

        if (state is MultiThumbnailCreationCancelled) {
          Navigator.of(context).pop();
        }

        if (state is MultiThumbnailCreationFilesLoadedEmpty) {
          Future.delayed(const Duration(seconds: 3), () {
            Navigator.of(context).pop();
          });
        }
      },
      builder: (context, state) {
        final typography = ArDriveTypographyNew.of(context);

        if (state is MultiThumbnailCreationInitial) {
          return Container();
        }

        if (state is MultiThumbnailCreationFilesLoadedEmpty) {
          return ArDriveStandardModalNew(
            content: Center(
              child: Text('No images missing thumbnails found in this drive!',
                  style: typography.paragraphLarge(
                      fontWeight: ArFontWeight.semiBold)),
            ),
            actions: [
              ModalAction(
                action: () {
                  Navigator.of(context).pop();
                },
                title: appLocalizationsOf(context).close,
              )
            ],
          );
        }

        if (state is MultiThumbnailCreationLoadingFiles) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (state is MultiThumbnailCreationFilesLoaded) {
          return Container();
        }

        if (state is MultiThumbnailCreationLoadingThumbnails) {
          return ArDriveStandardModalNew(
            title: 'Creating Thumbnails',
            actions: [
              ModalAction(
                action: () {
                  context
                      .read<MultiThumbnailCreationBloc>()
                      .add(CancelMultiThumbnailCreation());
                },
                title: appLocalizationsOf(context).cancel,
              )
            ],
            content: SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: state.thumbnails.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  final thumbnail = state.thumbnails[index];

                  return ListTile(
                      title: Text(thumbnail.file.name),
                      trailing: thumbnail.loaded
                          ? const Icon(Icons.check)
                          : const Text('Loading...'));
                },
              ),
            ),
          );
        }

        return Container();
      },
    );
  }
}
