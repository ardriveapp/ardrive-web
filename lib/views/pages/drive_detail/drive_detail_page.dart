import 'package:drive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'folder_view.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: BlocBuilder<DriveDetailBloc, DriveDetailState>(
          builder: (context, state) {
        return Column(
          children: <Widget>[
            if (state is FolderOpened) ...{
              _buildBreadcrumbRow(context, state.openedFolder.folder.path),
              Row(
                children: [
                  Expanded(
                    child: FolderView(
                      subfolders: state.openedFolder.subfolders,
                      files: state.openedFolder.files,
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

  Widget _buildBreadcrumbRow(BuildContext context, String path) {
    final pathSegments = path.split('/').where((s) => s != '').toList();

    return Row(
      children: pathSegments
          .asMap()
          .entries
          .map(
            (s) => InkWell(
              onTap: () => context.bloc<DriveDetailBloc>().add(
                    OpenFolder(
                      folderPath:
                          '/${pathSegments.sublist(0, s.key + 1).join('/')}',
                    ),
                  ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('/' + s.value),
              ),
            ),
          )
          .toList(),
    );
  }
}
