import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_shortcut/create_shortcut_cubit.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: unused_import

import 'package:reactive_forms/reactive_forms.dart';

import '../blocs/create_shortcut/create_shortcut_state.dart';
import 'components.dart';

Future<void> createShortcut({
  required BuildContext context,
  required DriveID driveId,
  required String folderInViewId,
  required String folderInViewPath,
  SecretKey? driveKey,
}) async {
  print(driveId);
  print(folderInViewId);
  print(folderInViewPath);
  print(driveKey);

  return showModalDialog(
    context,
    () => showDialog(
      context: context,
      builder: (BuildContext context) => CreateShortcutForm(
        driveId: driveId,
        folderInViewId: folderInViewId,
        folderInViewPath: folderInViewPath,
        driveKey: driveKey,
      ),
    ),
  );
}

/// Depends on a provided [DriveAttachCubit] for business logic.
class CreateShortcutForm extends StatelessWidget {
  const CreateShortcutForm(
      {Key? key,
      this.driveKey,
      required this.driveId,
      required this.folderInViewPath,
      required this.folderInViewId})
      : super(key: key);
  final SecretKey? driveKey;
  final String driveId;
  final String folderInViewPath;
  final String folderInViewId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateShortcutCubit>(
      create: (context) => CreateShortcutCubit(
        arweave:
            Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)),
        arweaveService: arweave,
        driveDao: context.read<DriveDao>(),
      ),
      child: BlocListener<CreateShortcutCubit, CreateShortcutState>(
        listener: (context, state) {
          if (state is CreateShortcutValidationSuccess) {
            context.read<CreateShortcutCubit>().createShortcut(
                  context,
                  folderInViewPath,
                  folderInViewId,
                  driveId,
                  driveKey,
                );
          }
        },
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
                  onPressed: () =>
                      context.read<CreateShortcutCubit>().isValid(),
                  child: Text('Create'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _getContent(CreateShortcutState state, BuildContext context) {
    print(state);
    if (state is CreateShortcutLoading ||
        state is CreateShortcutValidationSuccess) {
      return Container(child: const CircularProgressIndicator());
    } else if (state is CreateShortcutSuccess) {
      return Container(
        child: Text('its valid!'),
      );
    } else if (state is CreateShortcutError) {
      return Container(
        child: Text('Error!'),
      );
    } else if (state is CreateShortcutConflicting) {
      return Container(
        child: Text('There is a conflicting file: ${state.conflictingName}!'),
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
            ReactiveTextField(
              formControlName: 'fileName',
              autofocus: true,
              decoration: const InputDecoration(labelText: 'File name'),
              validationMessages:
                  kValidationMessages(appLocalizationsOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
