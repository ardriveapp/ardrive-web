import 'package:drive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../folder/folder_view.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: BlocBuilder<DriveDetailBloc, DriveDetailState>(
          builder: (context, state) {
        return Column(
          children: <Widget>[
            if (state is DriveOpened) ...{
              Row(children: [
                Text('/' + state.openedDrive.name),
                if (state is FolderOpened)
                  ...state.openedFolder.path
                      .split('/')
                      .where((s) => s != '')
                      .map((s) => InkWell(
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('/' + s),
                          ))),
              ]),
              if (state is FolderOpened)
                Row(
                  children: [
                    Expanded(
                      child: FolderView(
                        subfolders: state.subfolders,
                        files: state.files,
                      ),
                    ),
                  ],
                ),
            }
          ],
        );
      }),
    );
  }
}
