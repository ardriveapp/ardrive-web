import 'package:ardrive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_auth_shell.dart';

class ProfileAuthOnboarding extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          'assets/images/illustrations/illus_profile_onboarding.png',
          fit: BoxFit.scaleDown,
        ),
        content: FractionallySizedBox(
          widthFactor: 0.75,
          child: Column(
            children: [
              Text(
                'HOW DOES IT WORK?',
                style: Theme.of(context).textTheme.headline5,
              ),
              Container(height: 32),
              DefaultTextStyle(
                style: Theme.of(context).textTheme.headline6,
                child: Builder(
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ArDrive is a simple, yet robust app that protects and syncs your data to and from the cloud.',
                        style: DefaultTextStyle.of(context).style,
                      ),
                      Container(height: 16),
                      Text.rich(
                        TextSpan(
                          text: 'No subscription needed! ',
                          style: DefaultTextStyle.of(context).style,
                          children: <TextSpan>[
                            TextSpan(
                                text: 'Pay once',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(
                                text:
                                    ' to store your files, pictures, music, videos and apps permanently.'),
                          ],
                        ),
                      ),
                      Container(height: 16),
                      Text.rich(TextSpan(
                          text:
                              'Your Private Drive is encrypted, meaning ArDrive or anyone else can’t read your content. ',
                          style: DefaultTextStyle.of(context).style,
                          children: <TextSpan>[
                            TextSpan(
                                text: 'Only you!',
                                style: TextStyle(fontWeight: FontWeight.bold))
                          ])),
                      Container(height: 16),
                      Text.rich(TextSpan(
                          text:
                              'Your Public Drive is open for anyone on the internet to see. ',
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                                text: 'Post carefully!',
                                style: TextStyle(fontWeight: FontWeight.bold))
                          ])),
                      Container(height: 16),
                      Text.rich(TextSpan(
                          text:
                              'Any data uploaded is permanently stored and secured on a decentralized blockchain network. ',
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                                text: 'Deleting is not an option!',
                                style: TextStyle(fontWeight: FontWeight.bold))
                          ])),
                      Container(height: 16),
                      Text.rich(TextSpan(
                          text: 'Powered by the ',
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                                text: 'Arweave',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: ' Permaweb.')
                          ])),
                    ],
                  ),
                ),
              ),
              Container(height: 32),
              ElevatedButton(
                  child: Text('CONTINUE'),
                  onPressed: () =>
                      context.bloc<ProfileAddCubit>().completeOnboarding()),
            ],
          ),
        ),
      );
}
