import 'package:ardrive/theme/colors.dart';
import 'package:arweave/utils.dart' as utils;
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
                  onTap: () => toggleProfileOverlay(),
                ),
                Positioned(
                  top: 42,
                  right: 16,
                  height: 112,
                  width: 456,
                  child: BlocBuilder<ProfileCubit, ProfileState>(
                    builder: (context, state) => state is ProfileLoaded
                        ? Card(
                            elevation: 3,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(state.username),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          state.wallet.address,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyText2,
                                        ),
                                        Container(height: 4),
                                        Text(
                                          '${utils.winstonToAr(BigInt.parse(state.walletBalance))} AR',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline6
                                              .copyWith(
                                                color: kPrimarySwatch,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                        icon: Icon(Icons.logout),
                                        onPressed: () => context
                                            .bloc<ProfileCubit>()
                                            .signOut()),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Container(),
                  ),
                ),
              }
            ],
          );
        },
      );

  void toggleProfileOverlay() =>
      setState(() => showProfileOverlay = !showProfileOverlay);
}
