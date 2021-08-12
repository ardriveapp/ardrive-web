import 'package:ardrive/models/models.dart';
import 'package:flutter/material.dart';

class DriveListTile extends StatelessWidget {
  final Drive? drive;
  final bool selected;
  final VoidCallback? onPressed;

  const DriveListTile({this.drive, this.selected = false, this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListTile(
          trailing: drive!.isPrivate
              ? const Icon(
                  Icons.lock_outline,
                  size: 12,
                )
              : null,
          title: Text(
            drive!.name!,
            style: TextStyle(fontSize: 12),
          ),
          selected: selected,
          onTap: onPressed,
        ),
      );
}
