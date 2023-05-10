import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ResizableComponent extends StatefulWidget {
  final Widget child;
  final double maxHeight;
  final ScrollController scrollController;

  const ResizableComponent({
    super.key,
    required this.child,
    required this.scrollController,
    this.maxHeight = 87.0,
  });

  @override
  // ignore: library_private_types_in_public_api
  _ResizableComponentState createState() => _ResizableComponentState();
}

class _ResizableComponentState extends State<ResizableComponent> {
  double _height = 100.0; // initial height of the component

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (widget.scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      setState(() {
        if (_height < widget.maxHeight) {
          _height += 10.0; // increase height when scrolling up
        }
      });
    } else if (widget.scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      setState(() {
        _height -= 10.0; // decrease height when scrolling down
        if (_height < 0.0) {
          _height = 0.0; // cap height at 0
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _height,
      child: widget.child,
    );
  }
}

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.drive,
    required this.currentFolder,
    required this.driveDetailState,
  });

  final Drive drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ArDriveTheme.of(context).themeData.backgroundColor;
    return SafeArea(
      bottom: true,
      child: Container(
        height: 87,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .themeFgDefault
                  .withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
            BoxShadow(color: backgroundColor, offset: const Offset(0, 2)),
            BoxShadow(color: backgroundColor, offset: const Offset(-0, 8)),
          ],
          color: ArDriveTheme.of(context).themeData.backgroundColor,
        ),
        width: MediaQuery.of(context).size.width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            NewButton(
              drive: drive,
              currentFolder: currentFolder,
              driveDetailState: driveDetailState,
              dropdownWidth: 208,
            ),
          ],
        ),
      ),
    );
  }
}
