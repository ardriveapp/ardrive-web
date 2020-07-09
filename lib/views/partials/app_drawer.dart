import 'package:drive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesBloc, DrivesState>(
      builder: (context, state) => Drawer(
        elevation: 1,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FloatingActionButton.extended(
                  onPressed: () {},
                  label: Text('UPLOAD'),
                  icon: Icon(Icons.file_upload),
                ),
              ),
            ),
            if (state is DrivesReady)
              ...state.drives.map(
                (d) => ListTile(
                  leading: Icon(Icons.folder_shared),
                  title: Text(d.name),
                  selected: state.selectedDriveId == d.id,
                  onTap: () =>
                      context.bloc<DrivesBloc>().add(SelectDrive(d.id)),
                ),
              ),
            Expanded(child: Container()),
            Divider(height: 0),
            ListTile(
              title: Text('John Applebee'),
              subtitle: Text('john@arweave.org'),
              trailing: Icon(Icons.arrow_drop_down),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
