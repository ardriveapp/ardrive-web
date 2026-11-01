import 'package:ardrive/account/presentation/account_page.dart';
import 'package:ardrive/app_shell.dart';
import 'package:ardrive/billing/presentation/billing_sections.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// The Billing page in the app shell: a drive chosen in the sidebar opens it,
/// as on the Account and Names pages.
class BillingShell extends StatelessWidget {
  const BillingShell({super.key, required this.onOpenDrive});

  final void Function(String driveId) onOpenDrive;

  @override
  Widget build(BuildContext context) {
    return OpenDriveOnSelection(
      selections: context.read<DrivesCubit>().driveSelections,
      onOpenDrive: onOpenDrive,
      child: const AppShell(page: BillingPage()),
    );
  }
}

/// Billing: Turbo Credits, purchases and shared credits. Full screen with a
/// back arrow on a phone; in the main area on desktop.
class BillingPage extends StatelessWidget {
  const BillingPage({super.key, this.body});

  /// The page's content; [BillingSections] unless a test passes its own.
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final content = body ?? const BillingSections();
    final title = appLocalizationsOf(context).billing;

    return ScreenTypeLayout.builder(
      mobile: (context) => PhonePage(
        title: title,
        backKey: const Key('billingBack'),
        onBack: () => context.read<AppRouterDelegate>().closeBilling(),
        child: content,
      ),
      desktop: (context) => ListPageChrome(
        child: ReadablePageBody(
          title: title,
          capWidth: false,
          child: content,
        ),
      ),
    );
  }
}
