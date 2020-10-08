import 'package:flutter/material.dart';

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
