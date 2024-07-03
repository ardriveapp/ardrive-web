import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/drive_explorer/multi_thumbnail_creation/bloc/multi_thumbnail_creation_bloc.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MultiThumbnailCreationWrapper extends StatefulWidget {
  const MultiThumbnailCreationWrapper({required this.child, super.key});

  final Widget child;

  @override
  State<MultiThumbnailCreationWrapper> createState() =>
      _MultiThumbnailCreationWrapperState();
}

class _MultiThumbnailCreationWrapperState
    extends State<MultiThumbnailCreationWrapper> {
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
  }

  void _showOverlay(BuildContext context) {
    _overlayEntry =
        _createOverlayEntry(context.read<MultiThumbnailCreationBloc>());
    Overlay.of(context).insert(_overlayEntry!);
  }

  OverlayEntry _createOverlayEntry(MultiThumbnailCreationBloc bloc) {
    return OverlayEntry(
      builder: (context) => Positioned(
        bottom: 0,
        right: 20,
        child: BlocProvider.value(
          value: bloc,
          child: MultiThumbnailCreationModalContent(
            bloc: bloc,
          ),
        ),
      ),
    );
  }

  @override
  dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => BlocProvider(
            create: (context) => MultiThumbnailCreationBloc(
                driveRepository: DriveRepository(
                  driveDao: context.read<DriveDao>(),
                  auth: context.read<ArDriveAuth>(),
                ),
                thumbnailRepository: context.read<ThumbnailRepository>()),
            child: BlocListener<MultiThumbnailCreationBloc,
                MultiThumbnailCreationState>(
              listener: (context, state) {
                if (state is MultiThumbnailCreationThumbnailsLoaded ||
                    state is MultiThumbnailCreationCancelled) {
                  _overlayEntry?.remove();
                }

                if (state is MultiThumbnailCreationLoadingFiles) {
                  _showOverlay(context);
                }
              },
              child: widget.child,
            ),
          ),
        )
      ],
    );
  }
}

class MultiThumbnailCreationModalContent extends StatefulWidget {
  const MultiThumbnailCreationModalContent({required this.bloc, super.key});

  final MultiThumbnailCreationBloc bloc;

  @override
  State<MultiThumbnailCreationModalContent> createState() =>
      _MultiThumbnailCreationModalContentState();
}

class _MultiThumbnailCreationModalContentState
    extends State<MultiThumbnailCreationModalContent> {
  bool isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MultiThumbnailCreationBloc,
        MultiThumbnailCreationState>(
      bloc: widget.bloc,
      listener: (context, state) {},
      builder: (context, state) {
        final typography = ArDriveTypographyNew.of(context);

        if (state is MultiThumbnailCreationInitial) {
          return Container();
        }

        if (state is MultiThumbnailCreationFilesLoadedEmpty) {
          return Material(
            borderRadius: BorderRadius.circular(modalBorderRadius),
            child: ArDriveStandardModalNew(
              content: Center(
                child: Text('No images missing thumbnails found!',
                    style: typography.paragraphLarge(
                        fontWeight: ArFontWeight.semiBold)),
              ),
              actions: [
                ModalAction(
                  action: () {
                    context
                        .read<MultiThumbnailCreationBloc>()
                        .add(CancelMultiThumbnailCreation());
                  },
                  title: appLocalizationsOf(context).close,
                )
              ],
            ),
          );
        }

        if (state is MultiThumbnailCreationError) {
          return Material(
            child: ArDriveStandardModalNew(
              content: Center(
                child: Text('An error occurred while creating thumbnails!',
                    style: typography.paragraphLarge(
                        fontWeight: ArFontWeight.semiBold)),
              ),
              actions: [
                ModalAction(
                  action: () {
                    context
                        .read<MultiThumbnailCreationBloc>()
                        .add(CancelMultiThumbnailCreation());
                  },
                  title: appLocalizationsOf(context).close,
                )
              ],
            ),
          );
        }

        if (state is MultiThumbnailCreationLoadingFiles) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (state is MultiThumbnailCreationLoadingThumbnails) {
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

          if (isCollapsed) {
            return ArDriveCard(
              height: 64,
              width: 400,
              elevation: 2,
              withRedLineOnTop: true,
              contentPadding: EdgeInsets.zero,
              boxShadow: BoxShadowCard.shadow80,
              content: Material(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Text(
                              '${state.loadedDrives} / ${state.numberOfDrives} drives processed',
                              style: typography.paragraphLarge(
                                  fontWeight: ArFontWeight.bold)),
                          const Spacer(),
                          ArDriveIconButton(
                            icon: ArDriveIcons.carretUp(),
                            onPressed: () {
                              setState(() {
                                isCollapsed = false;
                              });
                            },
                          ),
                          ArDriveIconButton(
                            icon: ArDriveIcons.x(),
                            onPressed: () {
                              widget.bloc.add(CancelMultiThumbnailCreation());
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ArDriveCard(
            height: 202,
            width: 400,
            elevation: 2,
            contentPadding: EdgeInsets.zero,
            boxShadow: BoxShadowCard.shadow80,
            content: Material(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 6,
                    child: Container(
                      color: colorTokens.containerRed,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (state.driveInExecution != null)
                                RichText(
                                  text: TextSpan(children: [
                                    TextSpan(
                                      text: 'Drive in Execution: ',
                                      style: typography.paragraphLarge(
                                        fontWeight: ArFontWeight.semiBold,
                                        color: colorTokens.textHigh,
                                      ),
                                    ),
                                    TextSpan(
                                      text: state.driveInExecution!.name,
                                      style: typography.paragraphLarge(
                                        fontWeight: ArFontWeight.bold,
                                        color: colorTokens.textHigh,
                                      ),
                                    ),
                                  ]),
                                ),
                              const Spacer(),
                              ArDriveIconButton(
                                onPressed: () {
                                  widget.bloc.add(
                                      const SkipDriveMultiThumbnailCreation());
                                },
                                icon: const ArDriveIcon(
                                    icon: Icons.skip_next_outlined),
                                tooltip: 'Skip drive',
                              ),
                              ArDriveIconButton(
                                icon: ArDriveIcons.carretDown(),
                                onPressed: () {
                                  setState(() {
                                    isCollapsed = true;
                                  });
                                },
                                tooltip: 'Collapse',
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Creating thumbnails for images without thumbnails...',
                              style: typography.paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ArDriveProgressBar(
                            key: Key(state.driveInExecution?.id.toString() ??
                                'driveInExecution'),
                            height: 10,
                            percentage: state.loadedThumbnailsInDrive /
                                state.thumbnailsInDrive.length,
                            indicatorColor: colorTokens.containerRed,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${state.loadedThumbnailsInDrive} / ${state.thumbnailsInDrive.length}',
                              style: typography.paragraphLarge(
                                fontWeight: ArFontWeight.semiBold,
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            'Drives processed: ${state.loadedDrives} of ${state.numberOfDrives}',
                            style: typography.paragraphLarge(
                                fontWeight: ArFontWeight.semiBold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: ArDriveClickArea(
                      child: GestureDetector(
                        onTap: () {
                          widget.bloc.add(CancelMultiThumbnailCreation());
                        },
                        child: Text(
                          'Cancel',
                          style: typography.paragraphNormal(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container();
      },
    );
  }
}
