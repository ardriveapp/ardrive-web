import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveInfoSideSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Drawer(
        elevation: 1,
        child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
          builder: (context, state) {
            if (state is DriveDetailLoadSuccess) {
              return BlocProvider<DriveInfoCubit>(
                create: (context) => DriveInfoCubit(
                  driveId: state.currentDrive.id,
                  folderId:
                      state.selectedItemIsFolder ? state.selectedItemId : null,
                  fileId:
                      state.selectedItemIsFolder ? null : state.selectedItemId,
                  driveDao: context.repository<DriveDao>(),
                ),
                child: DefaultTabController(
                  length: 2,
                  child: BlocBuilder<DriveInfoCubit, DriveInfoState>(
                    builder: (context, state) => state
                            is DriveInfoGeneralLoadSuccess
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(height: 8),
                              ListTile(
                                title: Text(state.name),
                                trailing: IconButton(
                                  icon: Icon(Icons.close),
                                  onPressed: () => context
                                      .bloc<DriveDetailCubit>()
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
                                    DataTable(
                                      headingRowHeight: 0,
                                      columns: const [
                                        DataColumn(label: Text('')),
                                        DataColumn(label: Text('')),
                                      ],
                                      rows: [
                                        if (state
                                            is DriveInfoDriveLoadSuccess) ...{
                                          DataRow(cells: [
                                            DataCell(Text('Drive ID')),
                                            DataCell(
                                                SelectableText(state.drive.id)),
                                          ]),
                                          DataRow(cells: [
                                            DataCell(Text('Privacy')),
                                            DataCell(Text(state.drive.privacy))
                                          ]),
                                        } else if (state
                                            is DriveInfoFolderLoadSuccess)
                                          ...{}
                                        else if (state
                                            is DriveInfoFileLoadSuccess) ...{
                                          DataRow(cells: [
                                            DataCell(Text('Size')),
                                            DataCell(
                                                Text(filesize(state.file.size)))
                                          ]),
                                        }
                                      ],
                                    ),
                                    Center(
                                        child: Text(
                                            'We\'re still working on this!')),
                                  ],
                                ),
                              )
                            ],
                          )
                        : Container(),
                  ),
                ),
              );
            } else {
              return Container();
            }
          },
        ),
      );
}
