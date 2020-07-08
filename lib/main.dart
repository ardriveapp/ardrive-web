import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import './theme/theme.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drive',
      theme: appTheme(),
      home: MyHomePage(title: 'Drive'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
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
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: BlocProvider(
                          create: (context) => FolderBloc(),
                          child: BlocBuilder<FolderBloc, FolderState>(
                            builder: (context, state) => DataTable(
                              columns: const <DataColumn>[
                                DataColumn(
                                  label: Text(
                                    'Name',
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Date added',
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Size',
                                  ),
                                ),
                              ],
                              rows: state is FolderLoadSuccess
                                  ? [
                                      ...state.subfolders.map(
                                        (f) => DataRow(
                                          cells: [
                                            DataCell(NameCell(
                                                name: f.name, isFolder: true)),
                                            DataCell(Text('15 January 2020')),
                                            DataCell(Text('27MB')),
                                          ],
                                        ),
                                      ),
                                      ...state.files.map(
                                        (f) => DataRow(
                                          cells: [
                                            DataCell(NameCell(name: f.name)),
                                            DataCell(Text('15 January 2020')),
                                            DataCell(Text('27MB')),
                                          ],
                                        ),
                                      ),
                                    ]
                                  : [],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NameCell extends StatelessWidget {
  final String name;
  final bool isFolder;

  NameCell({this.name, this.isFolder = false});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          isFolder
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8.0),
                  child: Icon(Icons.folder),
                )
              : Padding(padding: const EdgeInsetsDirectional.only(end: 32)),
          Text(name),
        ],
      );
}
