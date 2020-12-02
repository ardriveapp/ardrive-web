import 'package:ardrive/models/models.dart';
import 'package:flutter/material.dart';

class DriveListTile extends StatelessWidget {
  final Drive drive;
  final bool selected;
  final VoidCallback onPressed;

  const DriveListTile({this.drive, this.selected = false, this.onPressed});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: drive.isPrivate
            ? const Icon(Icons.folder)
            : const Icon(Icons.folder_shared),
        title: Text(drive.name),
        selected: selected,
        onTap: onPressed,
      );
}
