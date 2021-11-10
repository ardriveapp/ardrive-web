import 'package:ardrive/components/orphan_fixer_form.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:pedantic/pedantic.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:url_launcher/link.dart';

import 'blocs/blocs.dart';
import 'components/components.dart';
import 'components/wallet_switch_dialog.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  AppShell({Key? key, required this.page}) : super(key: key);

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _showProfileOverlay = false;
  bool _showWalletSwitchDialog = true;
  @override
  Widget build(BuildContext context) => BlocBuilder<DrivesCubit, DrivesState>(
        builder: (context, state) {
          onArConnectWalletSwitch(() {
            if (_showWalletSwitchDialog) {
              showDialog(
                context: context,
                builder: (context) => WalletSwitchDialog(),
              );
            }
            //Used to prevent the dialog being shown multiple times.
            _showWalletSwitchDialog = false;
          });
          AppBar _buildAppBar() => AppBar(
                // title: Image.asset(
                //   R.images.brand.logoHorizontalNoSubtitle,
                //   height: 64,
                //   fit: BoxFit.contain,
                // ),
                elevation: 0.0,
                backgroundColor: Colors.transparent,
                actions: [
                  Link(
                    uri: Uri.parse(
                        'https://community.xyz/#-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ'),
                    target: LinkTarget.blank,
                    builder: (context, onPressed) => IconButton(
                      icon: const Icon(Icons.people_alt),
                      tooltip: 'CommunityXYZ',
                      onPressed: onPressed,
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
                        portal: Padding(
                          padding: const EdgeInsets.only(top: 56),
                          child: ProfileOverlay(),
                        ),
                        portalAnchor: Alignment.topRight,
                        childAnchor: Alignment.topRight,
                        child: const Icon(Icons.account_circle),
                      ),
                    ),
                    tooltip: 'Profile',
                    onPressed: () => toggleProfileOverlay(),
                  ),
                ],
              );
          Widget _buildPage(scaffold) => BlocListener<SyncCubit, SyncState>(
                listener: (context, state) {
                  if (state is SyncEmpty && state.orphanParents.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: Duration(seconds: 30),
                        width: 500,
                        content: Text(
                          'Orphaned Files Detected.',
                        ),
                        action: SnackBarAction(
                          label: 'RECREATE FOLDERS',
                          onPressed: () {
                            state.orphanParents.values.forEach((parent) {
                              unawaited(
                                promptToReCreateFolder(
                                  context,
                                  driveId: parent.driveId,
                                  parentFolderId: parent.parentFolderId,
                                  folderId: parent.id,
                                ),
                              );
                            });
                          },
                        ),
                      ),
                    );
                  }
                },
                child: BlocBuilder<SyncCubit, SyncState>(
                  builder: (context, syncState) {
                    if (syncState is SyncInProgress) {
                      return Stack(
                        children: [
                          AbsorbPointer(
                            child: scaffold,
                          ),
                          SizedBox.expand(
                            child: Container(
                              color: Colors.black.withOpacity(0.5),
                            ),
                          ),
                          BlocBuilder<ProfileCubit, ProfileState>(
                            builder: (context, state) {
                              return FutureBuilder(
                                future: context
                                    .read<ProfileCubit>()
                                    .isCurrentProfileArConnect(),
                                builder: (BuildContext context,
                                    AsyncSnapshot snapshot) {
                                  if (snapshot.data ?? false) {
                                    return ProgressDialog(
                                      title:
                                          'Syncing... Please remain on this tab.',
                                    );
                                  } else {
                                    return ProgressDialog(
                                      title: 'Syncing... Please wait.',
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      );
                    } else {
                      return scaffold;
                    }
                  },
                ),
              );
          return ScreenTypeLayout(
            desktop: _buildPage(
              Row(
                children: [
                  AppDrawer(),
                  Expanded(
                    child: Scaffold(
                      appBar: _buildAppBar(),
                      body: widget.page,
                    ),
                  ),
                ],
              ),
            ),
            mobile: _buildPage(
              Scaffold(
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
            ),
          );
        },
      );

  void toggleProfileOverlay() =>
      setState(() => _showProfileOverlay = !_showProfileOverlay);
}
