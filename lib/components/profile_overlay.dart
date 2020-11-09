import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) => state is ProfileLoaded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 448),
                        child: ListTile(
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
                              Container(height: 4),
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
                              icon: Icon(Icons.logout),
                              onPressed: () =>
                                  context.read<ProfileCubit>().signOut()),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Container(),
      );
}
