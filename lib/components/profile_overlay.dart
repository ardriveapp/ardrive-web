import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/link.dart';

class ProfileOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, state) => state is ProfileLoggedIn
                      ? ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(state.username),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.wallet.address,
                                style: Theme.of(context).textTheme.bodyText2,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${utils.winstonToAr(state.walletBalance)} AR',
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
                            icon: const Icon(Icons.logout),
                            tooltip: 'Logout',
                            onPressed: () =>
                                context.read<ProfileCubit>().logoutProfile(),
                          ),
                        )
                      : ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('You\'re not logged in'),
                          subtitle: Text(
                              'Log in to experience all of ArDrive\'s features!'),
                          trailing: Link(
                            uri: Uri(path: '/'),
                            builder: (context, onPressed) => IconButton(
                              icon: const Icon(Icons.login),
                              tooltip: 'Login',
                              onPressed: onPressed,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      );
}
