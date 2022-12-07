import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_shortcut/create_shortcut_cubit.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: unused_import

import 'package:reactive_forms/reactive_forms.dart';

import '../blocs/create_shortcut/create_shortcut_state.dart';
import 'components.dart';

Future<void> createShortcut({
  required BuildContext context,
  DriveID? driveId,
  String? driveName,
  SecretKey? driveKey,
}) {
  return showModalDialog(
    context,
    () => showDialog(
      context: context,
      builder: (BuildContext context) => const CreateShortcutForm(),
    ),
  );
}

/// Depends on a provided [DriveAttachCubit] for business logic.
class CreateShortcutForm extends StatelessWidget {
  const CreateShortcutForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateShortcutCubit>(
      create: (context) => CreateShortcutCubit(),
      child: BlocBuilder<CreateShortcutCubit, CreateShortcutState>(
        builder: (context, state) {
          return AppDialog(
            title: 'Create shortcut',
            content: _getContent(state, context),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(appLocalizationsOf(context).cancelEmphasized),
              ),
              ElevatedButton(
                onPressed: () => context.read<CreateShortcutCubit>().isValid(),
                child: Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _getContent(CreateShortcutState state, BuildContext context) {
    if (state is CreateShortcutLoading) {
      return Container(child: const CircularProgressIndicator());
    } else if (state is CreateShortcutSuccess) {
      return Container(
        child: Text('its valid!'),
      );
    } else if (state is CreateShortcutError) {
      return Container(
        child: Text('Error!'),
      );
    }
    return SizedBox(
      width: kMediumDialogWidth,
      child: ReactiveForm(
        formGroup: context.read<CreateShortcutCubit>().form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReactiveTextField(
              formControlName: 'shortcut',
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Transaction id'),
              validationMessages:
                  kValidationMessages(appLocalizationsOf(context)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
