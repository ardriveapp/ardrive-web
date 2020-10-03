import 'package:drive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components/add_profile_form.dart';
import 'components/unlock_profile_form.dart';

class ProfileAuthView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Material(
        child: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            Widget form;
            if (state is ProfilePromptAdd) {
              form = AddProfileForm();
            } else if (state is ProfilePromptUnlock) {
              form = UnlockProfileForm();
            } else {
              form = CircularProgressIndicator();
            }

            return Row(
              children: [
                Expanded(child: Container(color: Colors.grey)),
                Expanded(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      child: form,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}
