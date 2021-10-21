import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'profile_auth_fail_screen.dart';
import 'profile_auth_shell.dart';

class ProfileAuthUnlockScreen extends StatefulWidget {
  @override
  _ProfileAuthUnlockScreenState createState() =>
      _ProfileAuthUnlockScreenState();
}

class _ProfileAuthUnlockScreenState extends State<ProfileAuthUnlockScreen> {
  @override
  Widget build(BuildContext context) => BlocProvider<ProfileUnlockCubit>(
        create: (context) => ProfileUnlockCubit(
          profileCubit: context.read<ProfileCubit>(),
          profileDao: context.read<ProfileDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: BlocBuilder<ProfileUnlockCubit, ProfileUnlockState>(
          builder: (context, state) {
            if (state is ProfileUnlockFailure) {
              return ProfileAuthFailScreen();
            } else {
              return ProfileAuthShell(
                illustration: Image.asset(
                  R.images.profile.profileUnlock,
                  fit: BoxFit.contain,
                ),
                contentWidthFactor: 0.5,
                content: state is ProfileUnlockInitial
                    ? ReactiveForm(
                        formGroup: context.watch<ProfileUnlockCubit>().form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'WELCOME BACK, ${state.username!.toUpperCase()}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headline5,
                            ),
                            const SizedBox(height: 32),
                            ReactiveTextField(
                              formControlName: 'password',
                              autofocus: true,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock),
                              ),
                              autofillHints: [AutofillHints.password],
                              onSubmitted: () =>
                                  context.read<ProfileUnlockCubit>().submit(),
                              validationMessages: (_) => kValidationMessages,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () =>
                                    context.read<ProfileUnlockCubit>().submit(),
                                child: Text('UNLOCK'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () =>
                                  context.read<ProfileCubit>().logoutProfile(),
                              child: Text(
                                'Forget wallet and change profile',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(),
              );
            }
          },
        ),
      );
}
