part of '../drive_detail_page.dart';

class FsEntrySideSheet extends StatelessWidget {
  final String driveId;
  final String folderId;
  final String fileId;

  bool get _isShowingDriveDetails => folderId == null && fileId == null;

  FsEntrySideSheet({@required this.driveId, this.folderId, this.fileId});

  @override
  Widget build(BuildContext context) => Drawer(
        elevation: 1,
        child: BlocProvider<FsEntryInfoCubit>(
          // Specify a key to ensure a new cubit is provided when the folder/file id changes.
          key: ValueKey(driveId + (folderId ?? fileId ?? '')),
          create: (context) => FsEntryInfoCubit(
            driveId: driveId,
            folderId: folderId,
            fileId: fileId,
            driveDao: context.read<DriveDao>(),
          ),
          child: DefaultTabController(
            length: 2,
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
                          tabs: const [
                            Tab(text: 'DETAILS'),
                            Tab(text: 'ACTIVITY'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildInfoTab(context, state),
                              _buildActivityTab(context, state),
                            ],
                          ),
                        )
                      ],
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      );

  Widget _buildInfoTab(BuildContext context, FsEntryInfoSuccess state) =>
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
              DataCell(Text('Drive ID')),
              DataCell(SelectableText(state.entry.id)),
            ]),
            DataRow(cells: [
              DataCell(Text('Privacy')),
              DataCell(Text(state.entry.privacy))
            ]),
          } else if (state is FsEntryInfoSuccess<FolderEntry>) ...{
            DataRow(cells: [
              DataCell(Text('Folder ID')),
              DataCell(SelectableText(state.entry.id)),
            ]),
          } else if (state is FsEntryInfoSuccess<FileEntry>) ...{
            DataRow(cells: [
              DataCell(Text('File ID')),
              DataCell(SelectableText(state.entry.id)),
            ]),
            DataRow(cells: [
              DataCell(Text('Size')),
              DataCell(Text(filesize(state.entry.size)))
            ]),
            DataRow(cells: [
              DataCell(Text('Last modified')),
              DataCell(
                  Text(yMMdDateFormatter.format(state.entry.lastModifiedDate)))
            ]),
          },
          DataRow(cells: [
            DataCell(Text('Last updated')),
            DataCell(Text(yMMdDateFormatter.format(state.lastUpdated))),
          ]),
          DataRow(cells: [
            DataCell(Text('Date created')),
            DataCell(Text(yMMdDateFormatter.format(state.dateCreated))),
          ]),
        ],
      );

  Widget _buildActivityTab(BuildContext context, FsEntryInfoSuccess state) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: !_isShowingDriveDetails
            ? BlocProvider(
                create: (context) => FsEntryActivityCubit(
                  driveId: driveId,
                  folderId: folderId,
                  fileId: fileId,
                  driveDao: context.read<DriveDao>(),
                ),
                child: BlocBuilder<FsEntryActivityCubit, FsEntryActivityState>(
                  builder: (context, state) {
                    if (state is FsEntryActivitySuccess) {
                      if (state.revisions.isNotEmpty) {
                        return ListView.separated(
                          itemBuilder: (BuildContext context, int index) {
                            final revision = state.revisions[index];

                            Widget content;
                            Widget dateCreatedSubtitle;
                            String revisionConfirmationStatus;

                            if (revision is FolderRevisionWithTransaction) {
                              switch (revision.action) {
                                case RevisionAction.create:
                                  content = Text(
                                      'This folder was created with the name ${revision.name}.');
                                  break;
                                case RevisionAction.rename:
                                  content = Text(
                                      'This folder was renamed to ${revision.name}.');
                                  break;
                                case RevisionAction.move:
                                  content = Text('This folder was moved.');
                                  break;
                                default:
                                  content = Text('This folder was modified');
                              }

                              dateCreatedSubtitle = Text(yMMdDateFormatter
                                  .format(revision.dateCreated));

                              revisionConfirmationStatus =
                                  revision.confirmationStatus;
                            } else if (revision
                                is FileRevisionWithTransactions) {
                              switch (revision.action) {
                                case RevisionAction.create:
                                  content = Text(
                                      'This file was created with the name ${revision.name}.');
                                  break;
                                case RevisionAction.rename:
                                  content = Text(
                                      'This file was renamed to ${revision.name}.');
                                  break;
                                case RevisionAction.move:
                                  content = Text('This file was moved.');
                                  break;
                                case RevisionAction.uploadNewVersion:
                                  content = Text(
                                      'A new version of this file was uploaded.');
                                  break;
                                default:
                                  content = Text('This file was modified');
                              }

                              dateCreatedSubtitle = Text(yMMdDateFormatter
                                  .format(revision.dateCreated));

                              revisionConfirmationStatus =
                                  revision.confirmationStatus;
                            }

                            Widget statusIcon;
                            if (revisionConfirmationStatus ==
                                TransactionStatus.pending) {
                              statusIcon = Tooltip(
                                message: 'Pending',
                                child: const Icon(Icons.pending),
                              );
                            } else if (revisionConfirmationStatus ==
                                TransactionStatus.confirmed) {
                              statusIcon = Tooltip(
                                message: 'Confirmed',
                                child: const Icon(Icons.check),
                              );
                            } else if (revisionConfirmationStatus ==
                                TransactionStatus.failed) {
                              statusIcon = Tooltip(
                                message: 'Failed',
                                child: const Icon(Icons.error_outline),
                              );
                            }

                            return ListTile(
                              title: DefaultTextStyle(
                                style: Theme.of(context).textTheme.subtitle2,
                                child: content,
                              ),
                              subtitle: DefaultTextStyle(
                                style: Theme.of(context).textTheme.caption,
                                child: dateCreatedSubtitle,
                              ),
                              trailing: statusIcon,
                            );
                          },
                          separatorBuilder: (context, index) => Divider(),
                          itemCount: state.revisions.length,
                        );
                      } else {
                        return Center(
                            child: Text('This item is being processed...'));
                      }
                    } else {
                      return const Center(child: CircularProgressIndicator());
                    }
                  },
                ),
              )
            : Center(child: Text('We\'re still working on this!')),
      );
}
