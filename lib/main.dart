import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/drive.dart';
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
      title: 'Flutter Demo',
      theme: appTheme(),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
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
            create: (context) => DriveBloc(),
            child: BlocBuilder<DriveBloc, DriveState>(
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
                              .bloc<DriveBloc>()
                              .add(DriveAddedEvent(Drive(name: 'Stuff'))),
                          label: Text('UPLOAD'),
                          icon: Icon(Icons.file_upload),
                        ),
                      ),
                    ),
                    ...(state is DriveLoadSuccess
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
                        child: DataTable(
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
                          rows: [
                            DataRow(
                              cells: <DataCell>[
                                DataCell(
                                    NameCell(name: 'Secrets', isFolder: true)),
                                DataCell(Text('15 January 2020')),
                                DataCell(Text('27MB')),
                              ],
                            ),
                            DataRow(
                              cells: <DataCell>[
                                DataCell(
                                    NameCell(name: 'dog.png', isFolder: false)),
                                DataCell(Text('15 January 2020')),
                                DataCell(Text('27MB')),
                              ],
                            ),
                            DataRow(
                              cells: <DataCell>[
                                DataCell(
                                    NameCell(name: 'cat.jpg', isFolder: false)),
                                DataCell(Text('16 January 2020')),
                                DataCell(Text('47GB')),
                              ],
                            ),
                            DataRow(
                              cells: <DataCell>[
                                DataCell(NameCell(
                                    name: 'movies.zip', isFolder: false)),
                                DataCell(Text('18 January 2020')),
                                DataCell(Text('1MB')),
                              ],
                            ),
                          ],
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
