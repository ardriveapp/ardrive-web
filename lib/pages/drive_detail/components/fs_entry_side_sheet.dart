import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_activity/fs_entry_activity_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

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
              builder: (context, state) => state is FsEntryGeneralLoadSuccess
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
                              _buildInfoTab(state),
                              _buildActivityTab(state),
                            ],
                          ),
                        )
                      ],
                    )
                  : Container(),
            ),
          ),
        ),
      );

  Widget _buildInfoTab(FsEntryGeneralLoadSuccess state) => DataTable(
        // Hide the data table header.
        headingRowHeight: 0,
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
        ],
        rows: [
          if (state is FsEntryDriveLoadSuccess) ...{
            DataRow(cells: [
              DataCell(Text('Drive ID')),
              DataCell(SelectableText(state.drive.id)),
            ]),
            DataRow(cells: [
              DataCell(Text('Privacy')),
              DataCell(Text(state.drive.privacy))
            ]),
          } else if (state is FsEntryFolderLoadSuccess)
            ...{}
          else if (state is FsEntryFileLoadSuccess) ...{
            DataRow(cells: [
              DataCell(Text('Size')),
              DataCell(Text(filesize(state.file.size)))
            ]),
            DataRow(cells: [
              DataCell(Text('Last modified')),
              DataCell(
                  Text(DateFormat.yMMMd().format(state.file.lastModifiedDate)))
            ]),
          },
          DataRow(cells: [
            DataCell(Text('Last updated')),
            DataCell(Text(DateFormat.yMMMd().format(state.lastUpdated))),
          ]),
          DataRow(cells: [
            DataCell(Text('Date created')),
            DataCell(Text(DateFormat.yMMMd().format(state.dateCreated))),
          ]),
        ],
      );

  Widget _buildActivityTab(FsEntryGeneralLoadSuccess state) => Padding(
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
                      return ListView.separated(
                        itemBuilder: (BuildContext context, int index) {
                          final revision = state.revisions[index];

                          Widget content;
                          Widget dateCreated;

                          if (revision is FolderRevision) {
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

                            dateCreated = Text(DateFormat.yMMMd()
                                .format(revision.dateCreated));
                          } else if (revision is FileRevision) {
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

                            dateCreated = Text(DateFormat.yMMMd()
                                .format(revision.dateCreated));
                          }

                          return ListTile(
                            title: DefaultTextStyle(
                              style: Theme.of(context).textTheme.subtitle2,
                              child: content,
                            ),
                            subtitle: DefaultTextStyle(
                              style: Theme.of(context).textTheme.caption,
                              child: dateCreated,
                            ),
                          );
                        },
                        separatorBuilder: (context, index) => Divider(),
                        itemCount: state.revisions.length,
                      );
                    } else {
                      return Center(child: CircularProgressIndicator());
                    }
                  },
                ),
              )
            : Center(child: Text('We\'re still working on this!')),
      );
}
