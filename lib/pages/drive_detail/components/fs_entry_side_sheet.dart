import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

class FsEntrySideSheet extends StatelessWidget {
  final String driveId;
  final String folderId;
  final String fileId;

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

  Widget _buildActivityTab(FsEntryGeneralLoadSuccess state) =>
      Center(child: Text('We\'re still working on this!'));
}
