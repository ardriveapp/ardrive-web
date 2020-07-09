import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:drive/theme/theme.dart';
import 'package:drive/views/views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DriveRepository>(
          create: (context) => DriveRepository(),
        ),
      ],
      child: MaterialApp(
        title: 'Drive',
        theme: appTheme(),
        home: AppShell(title: 'Drive'),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  AppShell({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          BlocProvider(
            create: (context) => DrivesBloc(),
            child: BlocBuilder<DrivesBloc, DrivesState>(
              builder: (context, state) => Drawer(
                elevation: 1,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: FloatingActionButton.extended(
                          onPressed: () => context
                              .bloc<DrivesBloc>()
                              .add(DriveAdded(Drive(name: 'Stuff'))),
                          label: Text('UPLOAD'),
                          icon: Icon(Icons.file_upload),
                        ),
                      ),
                    ),
                    ...(state is DrivesLoadSuccess
                        ? state.drives.map(
                            (d) => ListTile(
                              leading: Icon(Icons.folder_shared),
                              title: Text(d.name),
                            ),
                          )
                        : [Container()]),
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
            ),
          ),
          Expanded(
            child: BlocProvider(
              create: (context) => DriveDetailBloc(),
              child: DriveDetailPage(),
            ),
          ),
        ],
      ),
    );
  }
}
