part of '../drive_detail_page.dart';

class FsEntrySideSheet extends StatefulWidget {
  final String driveId;
  final Privacy drivePrivacy;
  final SelectedItem? maybeSelectedItem;
  FsEntrySideSheet({
    required this.driveId,
    required this.drivePrivacy,
    this.maybeSelectedItem,
  });

  @override
  State<FsEntrySideSheet> createState() => _FsEntrySideSheetState();
}

class _FsEntrySideSheetState extends State<FsEntrySideSheet> {
  @override
  Widget build(BuildContext context) => Drawer(
        elevation: 1,
        child: MultiBlocProvider(
          // Specify a key to ensure a new cubit is provided when the folder/file id changes.
          key: widget.maybeSelectedItem?.id != null
              ? ValueKey(
                  widget.driveId + '${widget.maybeSelectedItem?.id}',
                )
              : UniqueKey(),
          providers: [
            BlocProvider<FsEntryInfoCubit>(
              create: (context) => FsEntryInfoCubit(
                driveId: widget.driveId,
                maybeSelectedItem: widget.maybeSelectedItem,
                driveDao: context.read<DriveDao>(),
              ),
            ),
            BlocProvider<FsEntryPreviewCubit>(
              create: (context) => FsEntryPreviewCubit(
                driveId: widget.driveId,
                maybeSelectedItem: widget.maybeSelectedItem,
                driveDao: context.read<DriveDao>(),
                profileCubit: context.read<ProfileCubit>(),
                arweave: context.read<ArweaveService>(),
                config: context.read<AppConfig>(),
              ),
            )
          ],
          child: BlocBuilder<FsEntryPreviewCubit, FsEntryPreviewState>(
            builder: (context, previewState) {
              return DefaultTabController(
                length: previewState is FsEntryPreviewSuccess ? 3 : 2,
                child: BlocBuilder<FsEntryInfoCubit, FsEntryInfoState>(
                  builder: (context, state) => state is FsEntryInfoSuccess
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            ListTile(
                              title: Text(state.name),
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => context
                                    .read<DriveDetailCubit>()
                                    .toggleSelectedItemDetails(),
                              ),
                            ),
                            TabBar(
                              tabs: [
                                if (previewState is FsEntryPreviewSuccess)
                                  Tab(
                                    text: appLocalizationsOf(context)
                                        .itemPreviewEmphasized,
                                  ),
                                Tab(
                                    text: appLocalizationsOf(context)
                                        .itemDetailsEmphasized),
                                Tab(
                                    text: appLocalizationsOf(context)
                                        .itemActivityEmphasized),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  if (previewState is FsEntryPreviewSuccess)
                                    Align(
                                        alignment: Alignment.topCenter,
                                        child: FsEntryPreviewWidget(
                                            state: previewState)),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildInfoTable(context, state),
                                      _buildTxTable(context, state),
                                    ],
                                  ),
                                  _buildActivityTab(context, state),
                                ],
                              ),
                            )
                          ],
                        )
                      : const SizedBox(),
                ),
              );
            },
          ),
        ),
      );

  Widget _buildInfoTable(BuildContext context, FsEntryInfoSuccess state) =>
      DataTable(
        // Hide the data table header.
        headingRowHeight: 0,
        dataTextStyle: Theme.of(context).textTheme.subtitle2,
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
        ],
        rows: [
          if (state is FsEntryInfoSuccess<Drive>) ...{
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).itemContains)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    fileAndFolderCountsToString(
                      fileCount: (state as FsEntryDriveInfoSuccess)
                          .rootFolderTree
                          .getRecursiveFileCount(),
                      folderCount:
                          state.rootFolderTree.getRecursiveSubFolderCount(),
                      localizations: appLocalizationsOf(context),
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).size)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    filesize((state).rootFolderTree.computeFolderSize()),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).driveID)),
              DataCell(
                CopyIconButton(
                  tooltip: appLocalizationsOf(context).copyDriveID,
                  value: state.entry.id,
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).privacy)),
              // Capitalise the privacy enums of drives for display.
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    state.entry.privacy == DrivePrivacy.private
                        ? appLocalizationsOf(context).private
                        : appLocalizationsOf(context).public,
                  ),
                ),
              )
            ]),
          } else if (state is FsEntryInfoSuccess<FolderNode>) ...{
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).itemContains)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    fileAndFolderCountsToString(
                      folderCount: state.entry.getRecursiveSubFolderCount(),
                      fileCount: state.entry.getRecursiveFileCount(),
                      localizations: appLocalizationsOf(context),
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).size)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    filesize(state.entry.computeFolderSize()),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).folderID)),
              DataCell(
                CopyIconButton(
                  tooltip: appLocalizationsOf(context).copyFolderID,
                  value: state.entry.folder.id,
                ),
              ),
            ]),
          } else if (state is FsEntryInfoSuccess<FileEntry>) ...{
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).fileID)),
              DataCell(
                CopyIconButton(
                  tooltip: appLocalizationsOf(context).copyFileID,
                  value: state.entry.id,
                ),
              ),
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).fileSize)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(filesize(state.entry.size)),
                ),
              )
            ]),
            DataRow(cells: [
              DataCell(Text(appLocalizationsOf(context).lastModified)),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    yMMdDateFormatter.format(state.entry.lastModifiedDate),
                  ),
                ),
              )
            ]),
          },
          DataRow(cells: [
            DataCell(Text(appLocalizationsOf(context).lastUpdated)),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  yMMdDateFormatter.format(state.lastUpdated),
                ),
              ),
            ),
          ]),
          DataRow(cells: [
            DataCell(Text(appLocalizationsOf(context).dateCreated)),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  yMMdDateFormatter.format(state.dateCreated),
                ),
              ),
            ),
          ]),
        ],
      );

  Widget _buildTxTable(BuildContext context, FsEntryInfoSuccess infoState) =>
      BlocProvider(
        create: (context) => FsEntryActivityCubit(
          driveId: widget.driveId,
          driveDao: context.read<DriveDao>(),
          maybeSelectedItem: widget.maybeSelectedItem,
        ),
        child: BlocBuilder<FsEntryActivityCubit, FsEntryActivityState>(
          builder: (context, state) {
            if (state is FsEntryActivitySuccess) {
              if (state.revisions.isNotEmpty) {
                final revision = state.revisions.first;
                return DataTable(
                  // Hide the data table header.

                  headingRowHeight: 0,
                  dataTextStyle: Theme.of(context).textTheme.subtitle2,
                  columns: const [
                    DataColumn(label: Text('')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    if (infoState is FsEntryDriveInfoSuccess) ...{
                      DataRow(cells: [
                        DataCell(Text(appLocalizationsOf(context).driveTxID)),
                        DataCell(
                          CopyIconButton(
                            tooltip: appLocalizationsOf(context).copyDriveTxID,
                            value: revision.metadataTx.id,
                          ),
                        ),
                      ]),
                      DataRow(cells: [
                        DataCell(
                            Text(appLocalizationsOf(context).rootFolderTxID)),
                        DataCell(
                          CopyIconButton(
                            tooltip:
                                appLocalizationsOf(context).copyRootFolderTxID,
                            value: infoState.rootFolderRevision.metadataTxId,
                          ),
                        ),
                      ]),
                      if (revision.bundledIn != null)
                        DataRow(cells: [
                          DataCell(
                              Text(appLocalizationsOf(context).bundleTxID)),
                          DataCell(
                            CopyIconButton(
                              tooltip:
                                  appLocalizationsOf(context).copyBundleTxID,
                              value: revision.bundledIn,
                            ),
                          ),
                        ]),
                    } else if (infoState is FsEntryInfoSuccess<FolderNode>) ...{
                      DataRow(cells: [
                        DataCell(
                            Text(appLocalizationsOf(context).metadataTxID)),
                        DataCell(
                          CopyIconButton(
                            tooltip:
                                appLocalizationsOf(context).copyMetadataTxID,
                            value: revision.metadataTx.id,
                          ),
                        ),
                      ]),
                    } else if (infoState is FsEntryInfoSuccess<FileEntry>) ...{
                      DataRow(cells: [
                        DataCell(
                            Text(appLocalizationsOf(context).metadataTxID)),
                        DataCell(
                          CopyIconButton(
                            tooltip:
                                appLocalizationsOf(context).copyMetadataTxID,
                            value: revision.metadataTx.id,
                          ),
                        ),
                      ]),
                      DataRow(cells: [
                        DataCell(Text(appLocalizationsOf(context).dataTxID)),
                        DataCell(
                          CopyIconButton(
                            tooltip: appLocalizationsOf(context).copyDataTxID,
                            value: revision.dataTx.id,
                          ),
                        ),
                      ]),
                      if (revision.bundledIn != null)
                        DataRow(cells: [
                          DataCell(
                              Text(appLocalizationsOf(context).bundleTxID)),
                          DataCell(
                            CopyIconButton(
                              tooltip:
                                  appLocalizationsOf(context).copyBundleTxID,
                              value: revision.bundledIn,
                            ),
                          ),
                        ]),
                    },
                  ],
                );
              } else {
                return Center(
                    child:
                        Text(appLocalizationsOf(context).itemIsBeingProcesed));
              }
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      );

  Widget _buildActivityTab(BuildContext context, FsEntryInfoSuccess state) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: BlocProvider(
          create: (context) => FsEntryActivityCubit(
            driveId: widget.driveId,
            maybeSelectedItem: widget.maybeSelectedItem,
            driveDao: context.read<DriveDao>(),
          ),
          child: BlocBuilder<FsEntryActivityCubit, FsEntryActivityState>(
            builder: (context, state) {
              if (state is FsEntryActivitySuccess) {
                if (state.revisions.isNotEmpty) {
                  return ListView.separated(
                    itemBuilder: (BuildContext context, int index) {
                      final revision = state.revisions[index];

                      late Widget content;
                      late Widget dateCreatedSubtitle;
                      late String revisionConfirmationStatus;

                      if (revision is DriveRevisionWithTransaction) {
                        switch (revision.action) {
                          case RevisionAction.create:
                            content = Text(appLocalizationsOf(context)
                                .driveWasCreatedWithName(revision.name));
                            break;
                          case RevisionAction.rename:
                            content = Text(appLocalizationsOf(context)
                                .driveWasRenamed(revision.name));
                            break;
                          default:
                            content = Text(
                                appLocalizationsOf(context).driveWasModified);
                        }

                        dateCreatedSubtitle = Text(
                            yMMdDateFormatter.format(revision.dateCreated));

                        revisionConfirmationStatus =
                            revision.confirmationStatus;
                      } else if (revision is FolderRevisionWithTransaction) {
                        switch (revision.action) {
                          case RevisionAction.create:
                            content = Text(appLocalizationsOf(context)
                                .folderWasCreatedWithName(revision.name));
                            break;
                          case RevisionAction.rename:
                            content = Text(appLocalizationsOf(context)
                                .folderWasRenamed(revision.name));
                            break;
                          case RevisionAction.move:
                            content = Text(
                                appLocalizationsOf(context).folderWasMoved);
                            break;
                          default:
                            content = Text(
                                appLocalizationsOf(context).folderWasModified);
                        }

                        dateCreatedSubtitle = Text(
                            yMMdDateFormatter.format(revision.dateCreated));

                        revisionConfirmationStatus =
                            revision.confirmationStatus;
                      } else if (revision is FileRevisionWithTransactions) {
                        final previewOrDownloadButton = InkWell(
                          onTap: () {
                            downloadOrPreviewRevision(
                              drivePrivacy: widget.drivePrivacy,
                              context: context,
                              revision: revision,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: widget.drivePrivacy ==
                                      DrivePrivacy.private
                                  ? [
                                      Text(
                                          appLocalizationsOf(context).download),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.download),
                                    ]
                                  : [
                                      Text(appLocalizationsOf(context).preview),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.open_in_new)
                                    ],
                            ),
                          ),
                        );

                        switch (revision.action) {
                          case RevisionAction.create:
                            content = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appLocalizationsOf(context)
                                      .fileWasCreatedWithName(revision.name),
                                ),
                                previewOrDownloadButton,
                              ],
                            );
                            break;
                          case RevisionAction.rename:
                            content = Text(appLocalizationsOf(context)
                                .fileWasRenamed(revision.name));
                            break;
                          case RevisionAction.move:
                            content =
                                Text(appLocalizationsOf(context).fileWasMoved);
                            break;
                          case RevisionAction.uploadNewVersion:
                            content = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(appLocalizationsOf(context)
                                    .fileHadANewRevision),
                                previewOrDownloadButton,
                              ],
                            );
                            break;
                          default:
                            content = Text(
                                appLocalizationsOf(context).fileWasModified);
                        }

                        dateCreatedSubtitle = Text(
                            yMMdDateFormatter.format(revision.dateCreated));

                        revisionConfirmationStatus = fileStatusFromTransactions(
                            revision.metadataTx, revision.dataTx);
                      }

                      late Widget statusIcon;
                      if (revisionConfirmationStatus ==
                          TransactionStatus.pending) {
                        statusIcon = Tooltip(
                          message: appLocalizationsOf(context).pending,
                          child: const Icon(Icons.pending),
                        );
                      } else if (revisionConfirmationStatus ==
                          TransactionStatus.confirmed) {
                        statusIcon = Tooltip(
                          message: appLocalizationsOf(context).confirmed,
                          child: const Icon(Icons.check),
                        );
                      } else if (revisionConfirmationStatus ==
                          TransactionStatus.failed) {
                        statusIcon = Tooltip(
                          message: appLocalizationsOf(context).failed,
                          child: const Icon(Icons.error_outline),
                        );
                      }

                      return ListTile(
                        title: DefaultTextStyle(
                          style: Theme.of(context).textTheme.subtitle2!,
                          child: content,
                        ),
                        subtitle: DefaultTextStyle(
                          style: Theme.of(context).textTheme.caption!,
                          child: dateCreatedSubtitle,
                        ),
                        trailing: statusIcon,
                      );
                    },
                    separatorBuilder: (context, index) => const Divider(),
                    itemCount: state.revisions.length,
                  );
                } else {
                  return Center(
                      child: Text(
                          appLocalizationsOf(context).itemIsBeingProcesed));
                }
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
        ),
      );
}

void downloadOrPreviewRevision({
  required String drivePrivacy,
  required BuildContext context,
  required FileRevisionWithTransactions revision,
}) {
  if (drivePrivacy == DrivePrivacy.private) {
    promptToDownloadProfileFile(
      context: context,
      driveId: revision.driveId,
      fileId: revision.fileId,
      dataTxId: revision.dataTxId,
    );
  } else {
    context.read<DriveDetailCubit>().launchPreview(revision.dataTxId);
  }
}

class CopyIconButton extends StatelessWidget {
  final String value;
  final String tooltip;

  CopyIconButton({required this.value, required this.tooltip});

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: const Icon(Icons.copy, color: Colors.black54),
          tooltip: tooltip,
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      );
}
