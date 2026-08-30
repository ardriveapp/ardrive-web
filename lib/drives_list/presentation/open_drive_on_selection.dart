import 'dart:async';

import 'package:flutter/widgets.dart';

/// Opens the drive the user chose, wherever in the shell they chose it.
///
/// The drives list is a page with a sidebar, and that sidebar lists every
/// drive. A tap there only ever selected a drive - which on the explorer is
/// the same thing as opening it, because the explorer draws whatever is
/// selected, and on this page is nothing at all: the page draws the list. So
/// the most obvious navigation control on the first screen a login sees did
/// nothing.
///
/// Selection is the signal because it is the one the sidebar already sends.
/// The stream is passed in rather than read off a cubit so this can be pumped
/// on its own, with no shell around it.
class OpenDriveOnSelection extends StatefulWidget {
  const OpenDriveOnSelection({
    super.key,
    required this.selections,
    required this.onOpenDrive,
    required this.child,
  });

  /// Drives the user has asked for, by id.
  final Stream<String> selections;

  /// What opening one means. Called once per selection, in order.
  final void Function(String driveId) onOpenDrive;

  final Widget child;

  @override
  State<OpenDriveOnSelection> createState() => _OpenDriveOnSelectionState();
}

class _OpenDriveOnSelectionState extends State<OpenDriveOnSelection> {
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(OpenDriveOnSelection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selections != widget.selections) {
      _listen();
    }
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.selections.listen((driveId) {
      if (!mounted) {
        return;
      }

      widget.onOpenDrive(driveId);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
