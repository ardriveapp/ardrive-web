import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void forgetWallet(
  BuildContext context,
) {
  final actions = [
    ModalAction(
      action: () {
        Navigator.pop(context);
      },
      title: appLocalizationsOf(context).cancel,
    ),
    ModalAction(
      action: () {
        Navigator.pop(context);

        context.read<LoginBloc>().add(const ForgetWallet());
      },
      title: appLocalizationsOf(context).ok,
    )
  ];
  showStandardDialog(
    context,
    title: appLocalizationsOf(context).forgetWalletTitle,
    description: appLocalizationsOf(context).forgetWalletDescription,
    actions: actions,
  );
}
