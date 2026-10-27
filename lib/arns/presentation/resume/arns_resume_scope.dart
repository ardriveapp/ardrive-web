import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/resume/arns_resume_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Around the signed-in app: once names are on, says what became of a name
/// change a reload interrupted, in the app's snackbar.
class ArNSResumeScope extends StatelessWidget {
  const ArNSResumeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_resumeOn(context)) return child;
    return BlocProvider(
      lazy: false,
      create: (context) => ArNSResumeCubit(
        store: context.read<ArNSPendingActionStore>(),
        client: context.read<TurboArNSActionClient>(),
        walletCubit: context.read<ArNSWalletCubit>(),
        namesCubit: context.read<ArNSNamesCubit>(),
      ),
      child: BlocListener<ArNSResumeCubit, ArNSResumeState>(
        listenWhen: (previous, current) =>
            current.notice != null && current.serial != previous.serial,
        listener: (context, state) =>
            showArNSResumeNotice(context, state.notice!),
        child: child,
      ),
    );
  }

  static bool _resumeOn(BuildContext context) {
    if (!arnsFlowNamesOn(context)) return false;
    try {
      context.read<ArNSPendingActionStore>();
      context.read<TurboArNSActionClient>();
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }
}

/// The notice for [notice].
void showArNSResumeNotice(BuildContext context, ArNSResumeNotice notice) {
  final strings = appLocalizationsOf(context);
  final typography = ArDriveTypographyNew.of(context);
  final colors = ArDriveTheme.of(context).themeData.colorTokens;
  final host = arnsHostFor(notice.name);
  final message = switch (notice.outcome) {
    ArNSResumeOutcome.saved => strings.arnsResumeSaved(host),
    ArNSResumeOutcome.refunding => strings.arnsResumeRefunding(host),
    ArNSResumeOutcome.expired => strings.arnsResumeExpired(host),
  };

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: typography.paragraphNormal(color: colors.textHigh),
      ),
      backgroundColor: colors.containerL3,
      duration: const Duration(seconds: 8),
    ),
  );
}
