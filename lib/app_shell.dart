import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_portal/flutter_portal.dart';

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
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: Image.asset(
              'assets/images/logo-horiz-beta-no-subtitle.png',
              height: 64,
              fit: BoxFit.contain,
            ),
            actions: [
              IconButton(
                icon: PortalEntry(
                  visible: showProfileOverlay,
                  portal: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => toggleProfileOverlay(),
                  ),
                  child: PortalEntry(
                    visible: showProfileOverlay,
                    portal: ProfileOverlay(),
                    portalAnchor: Alignment.topRight,
                    childAnchor: Alignment.centerLeft,
                    child: Icon(Icons.account_circle),
                  ),
                ),
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
        ),
      );

  void toggleProfileOverlay() =>
      setState(() => showProfileOverlay = !showProfileOverlay);
}
