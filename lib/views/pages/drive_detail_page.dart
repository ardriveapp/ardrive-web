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
        if (state is DriveDetailFolderOpenSuccess) {
          return Column(
            children: <Widget>[
              Row(
                children: state.selectedFolderPathSegments
                    .map((s) => InkWell(
                        onTap: () => context
                            .bloc<DriveDetailBloc>()
                            .add(OpenedFolder(s.folderId)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(s.folderName + '/'),
                        )))
                    .toList(),
              ),
              Row(
                children: [
                  Expanded(
                    child: FolderView(
                      subfolders: state.subfolders,
                      files: state.files,
                    ),
                  ),
                ],
              )
            ],
          );
        }

        return Container();
      }),
    );
  }
}
