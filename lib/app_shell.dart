import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:url_launcher/link.dart';

import 'blocs/blocs.dart';
import 'components/components.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  AppShell({Key key, this.page}) : super(key: key);

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _showProfileOverlay = false;

  @override
  Widget build(BuildContext context) => BlocBuilder<DrivesCubit, DrivesState>(
        builder: (context, state) {
          Widget _buildAppBar() => AppBar(
                title: Image.asset(
                  R.images.brand.logoHorizontalNoSubtitle,
                  height: 64,
                  fit: BoxFit.contain,
                ),
                actions: [
                  Link(
                    uri: Uri.parse(
                        'https://community.xyz/#-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ'),
                    target: LinkTarget.blank,
                    builder: (context, onPressed) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.people_alt),
                          tooltip: 'CommunityXYZ',
                          onPressed: onPressed,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: PortalEntry(
                      visible: _showProfileOverlay,
                      portal: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => toggleProfileOverlay(),
                      ),
                      child: PortalEntry(
                        visible: _showProfileOverlay,
                        portal: ProfileOverlay(),
                        portalAnchor: Alignment.topRight,
                        childAnchor: Alignment.centerLeft,
                        child: const Icon(Icons.account_circle),
                      ),
                    ),
                    tooltip: 'Profile',
                    onPressed: () => toggleProfileOverlay(),
                  ),
                ],
              );

          return ScreenTypeLayout(
            desktop: Scaffold(
              appBar: _buildAppBar(),
              body: Row(
                children: [
                  AppDrawer(),
                  Expanded(
                    child: widget.page,
                  ),
                ],
              ),
            ),
            mobile: Scaffold(
              appBar: _buildAppBar(),
              drawer: AppDrawer(),
              body: Row(
                children: [
                  Expanded(
                    child: widget.page,
                  ),
                ],
              ),
            ),
          );
        },
      );

  void toggleProfileOverlay() =>
      setState(() => _showProfileOverlay = !_showProfileOverlay);
}
