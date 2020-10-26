import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/blocs.dart';
import 'components/components.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  AppShell({Key key, this.page}) : super(key: key);

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool showProfileOverlay = false;

  @override
  Widget build(BuildContext context) => BlocBuilder<DrivesCubit, DrivesState>(
        builder: (context, state) {
          final content = Scaffold(
            appBar: AppBar(
              title: Image.asset(
                'assets/images/logo-horiz-no-subtitle.png',
                height: 64,
                fit: BoxFit.contain,
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.account_circle),
                  onPressed: () => toggleProfileOverlay(),
                ),
              ],
            ),
            body: Row(
              children: [
                AppDrawer(),
                Expanded(
                  child: widget.page,
                ),
              ],
            ),
          );

          return Stack(
            children: [
              content,
              if (showProfileOverlay) ...{
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => toggleProfileOverlay(),
                ),
                Positioned.fill(
                  top: 42,
                  right: 16,
                  child: ProfileOverlay(),
                ),
              }
            ],
          );
        },
      );

  void toggleProfileOverlay() =>
      setState(() => showProfileOverlay = !showProfileOverlay);
}
