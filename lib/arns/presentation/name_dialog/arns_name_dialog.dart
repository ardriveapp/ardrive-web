import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/arns/data/arns_file_metadata_writer.dart';
import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/domain/undername_validation.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_chooser.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/widgets/arns_widgets.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Phones get a bottom sheet; wider screens a dialog.
const arnsSheetBreakpoint = 600.0;

/// Opens the name dialog (docs/NAMES.md, "Name an item", "Removing", "The
/// Names page").
Future<void> showArNSNameDialog(
  BuildContext context, {
  required ArNSNameDialogMode mode,
  ArNSNameableItem? item,
  ArNSRecordChoice? choice,
}) {
  final config = context.read<ConfigService>().config;
  final driveDao = context.read<DriveDao>();
  final publications = context.read<PublicationRepository>();
  final arnsDao = context.read<Database>().aRNSDao;
  final auth = context.read<ArDriveAuth>();
  final arioSDK = ArioSDKFactory().create();
  final paymentService = context.read<PaymentService>();
  final namesCubit = context.read<ArNSNamesCubit>();
  final walletCubit = context.read<ArNSWalletCubit>();
  ProfileCubit? profileCubit;
  try {
    profileCubit = context.read<ProfileCubit>();
  } on ProviderNotFoundException {
    // Only in tests that open the dialog on its own.
  }

  // As Upload does: close, then sign out.
  Future<bool> Function()? walletMismatch(BuildContext dialogContext) {
    final profile = profileCubit;
    if (profile == null) return null;
    return () async {
      if (!await profile.checkIfWalletMismatch()) return false;
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      await profile.logoutProfile();
      return true;
    };
  }

  ArNSNameDialogCubit create(BuildContext dialogContext) => ArNSNameDialogCubit(
        walletMismatch: walletMismatch(dialogContext),
        mode: mode,
        item: item,
        choice: choice,
        namesCubit: namesCubit,
        walletCubit: walletCubit,
        actionClient: context.read<TurboArNSActionClient>(),
        executor: arnsChangeExecutor(context, arioSDK),
        arioSDK: arioSDK,
        metadataWriter: DriveDaoArNSFileMetadataWriter(
          driveDao: driveDao,
          arweave: context.read<ArweaveService>(),
          turboUploadService: context.read<TurboUploadService>(),
          paymentService: paymentService,
          auth: auth,
        ),
        paymentSource: ArDriveArNSPaymentSource(
          auth: auth,
          paymentService: paymentService,
        ),
        placeholderTxId: config.arnsPlaceholderTxId,
        searchItems: (query) async => [
          ...await searchNameablePublications(
            driveDao,
            publications,
            owner: auth.currentUser.walletAddress,
            query: query,
          ),
          ...await searchNameableItems(
            arnsDao,
            owner: auth.currentUser.walletAddress,
            query: query,
          ),
        ],
      )..load();

  Widget body(bool inSheet) => MultiBlocProvider(
        providers: [
          BlocProvider(create: create),
          BlocProvider.value(value: walletCubit),
          BlocProvider.value(value: namesCubit),
        ],
        child: ArNSNameDialog(inSheet: inSheet),
      );

  if (MediaQuery.sizeOf(context).width < arnsSheetBreakpoint) {
    return showArDriveBottomSheet(
      context,
      // A change in flight must not be swiped away.
      isDismissible: false,
      builder: (_) => body(true),
    );
  }
  return showArDriveDialog(
    context,
    barrierDismissible: false,
    content: body(false),
  );
}

/// The owner's publications, latest versions, to point a record at: named
/// by the drive or folder they show (docs/NAMES.md, Q5).
Future<List<ArNSNameableItem>> searchNameablePublications(
  DriveDao driveDao,
  PublicationRepository repository, {
  required String owner,
  required String query,
}) async {
  final Map<String, List<Publication>> byDrive;
  try {
    byDrive = await repository.publicationsOfOwner(owner);
  } catch (e) {
    return const [];
  }
  final needle = query.trim().toLowerCase();
  final items = <ArNSNameableItem>[];
  for (final publications in byDrive.values) {
    for (final publication in publications) {
      final latest = publication.latest;
      // Named as the owner knows it here, from this device's own records.
      final String? scopeName = switch (latest.scope) {
        PublicationDriveScope() =>
          (await driveDao.driveById(driveId: latest.driveId).getSingleOrNull())
              ?.name,
        PublicationFolderScope(:final folderId) =>
          (await driveDao.folderById(folderId: folderId).getSingleOrNull())
              ?.name,
        PublicationFileScope(:final fileId) =>
          (await driveDao.fileById(fileId: fileId).getSingleOrNull())?.name,
      };
      if (scopeName == null) continue;
      if (needle.isNotEmpty && !scopeName.toLowerCase().contains(needle)) {
        continue;
      }
      items.add(ArNSNameableItem.publication(
        publicationId: latest.publicationId,
        driveId: latest.driveId,
        name: scopeName,
        dataTxId: latest.txId,
      ));
    }
  }
  return items;
}

/// Public files and deployments in the owner's drives, to point a record at.
Future<List<ArNSNameableItem>> searchNameableItems(
  ARNSDao dao, {
  required String owner,
  required String query,
}) async {
  final escaped = query
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  final rows =
      await dao.nameableFiles(owner: owner, pattern: '%$escaped%').get();
  return [
    for (final row in rows)
      ArNSNameableItem(
        fileId: row.fileId,
        driveId: row.driveId,
        name: row.name,
        dataTxId: row.dataTxId,
        isManifest: row.dataContentType == ContentType.manifest,
      ),
  ];
}

class ArNSNameDialog extends StatefulWidget {
  const ArNSNameDialog({super.key, required this.inSheet});

  final bool inSheet;

  @override
  State<ArNSNameDialog> createState() => _ArNSNameDialogState();
}

class _ArNSNameDialogState extends State<ArNSNameDialog> {
  /// The wallet chooser, opened by "Link a Solana wallet".
  bool _choosingWallet = false;
  bool _changingWallet = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
      builder: (context, wallet) =>
          BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
        builder: (context, state) => _frame(context, state, wallet),
      ),
    );
  }

  Widget _frame(
    BuildContext context,
    ArNSNameDialogState state,
    ArNSWalletState wallet,
  ) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<ArNSNameDialogCubit>();
    void close() => Navigator.of(context).pop();

    final title = _title(context, state);
    late Widget content;
    var actions = <ModalAction>[];

    switch (state.stage) {
      case ArNSDialogStage.loading:
        content = ArNSWaitingLine(text: strings.arnsReadingNames);
        actions = [ModalAction.dismiss(title: strings.cancel, action: close)];
      case ArNSDialogStage.needsWallet:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ArNSBodyText(strings.arnsLinkWalletExplainer),
            const SizedBox(height: ArDriveSpacing.md),
            const ArNSWalletChooser(),
          ],
        );
        actions = [ModalAction.dismiss(title: strings.cancel, action: close)];
      case ArNSDialogStage.noNames:
        content = ArNSNoNames(onClose: close);
        actions = [ModalAction.dismiss(title: strings.close, action: close)];
      case ArNSDialogStage.loadFailed:
        content = ArNSBodyText(strings.arnsNamesCouldNotBeRead);
        actions = [
          ModalAction.dismiss(title: strings.close, action: close),
          ModalAction(
            title: strings.tryAgain,
            action: () => context.read<ArNSNamesCubit>().refresh(),
          ),
        ];
      case ArNSDialogStage.choose:
        content = _ChooseContent(
          state: state,
          wallet: wallet,
          choosingWallet: _choosingWallet,
          changingWallet: _changingWallet,
          onChangeWallet: () => setState(() {
            _choosingWallet = true;
            _changingWallet = true;
          }),
          onLinked: () => setState(() {
            _choosingWallet = false;
            _changingWallet = false;
          }),
        );
        actions = [
          ModalAction.dismiss(title: strings.cancel, action: close),
          _commitAction(context, state, wallet, cubit),
        ];
      case ArNSDialogStage.confirmRepoint:
        content = ArNSRepointQuestion(record: state.selectedRecord!);
        actions = [
          ModalAction.dismiss(title: strings.back, action: cubit.backToChoose),
          ModalAction(
            title: strings.arnsPointItHere,
            action: cubit.confirmRepoint,
          ),
        ];
      case ArNSDialogStage.committing:
        content = _Progress(state: state);
        actions = const [];
      case ArNSDialogStage.done:
        content = _Done(state: state);
        actions = [ModalAction(title: strings.doneEmphasized, action: close)];
      case ArNSDialogStage.failed:
        content = _Failed(state: state);
        actions = [
          ModalAction.dismiss(title: strings.close, action: close),
          if (state.failure?.kind == ArNSFailureKind.insufficientCredits)
            ModalAction(
              title: strings.arnsTopUp,
              action: () {
                close();
                showTurboTopupModal(context);
              },
            )
          else if (cubit.canTryAgain)
            ModalAction(title: strings.tryAgain, action: cubit.backToChoose),
        ];
    }

    if (widget.inSheet) {
      return ArDriveBottomSheet(
        title: title,
        content: content,
        actions: actions,
        // Shown not dismissible: a change in flight must not be left.
        hasCloseButton: false,
      );
    }
    return ArDriveStandardModalNew(
      title: title,
      width: 520,
      scrollableContent: true,
      content: content,
      actions: actions,
    );
  }

  /// The commit button is the wallet's next step until the wallet is ready
  /// (docs/NAMES.md, "Asked for at commit").
  ModalAction _commitAction(
    BuildContext context,
    ArNSNameDialogState state,
    ArNSWalletState wallet,
    ArNSNameDialogCubit cubit,
  ) {
    final strings = appLocalizationsOf(context);
    final ready = state.canCommit;
    switch (wallet.status) {
      case ArNSWalletStatus.unavailable:
      case ArNSWalletStatus.notLinked:
        return ModalAction(
          title: strings.arnsLinkSolanaWallet,
          isEnable: !_choosingWallet && !wallet.connecting,
          action: () => setState(() => _choosingWallet = true),
        );
      case ArNSWalletStatus.disconnected:
      case ArNSWalletStatus.wrongAccount:
        return ModalAction(
          title: strings.arnsReconnectSolanaWallet,
          isEnable: !wallet.connecting,
          action: () async {
            final walletCubit = context.read<ArNSWalletCubit>();
            if (wallet.linked?.walletName == null || wallet.noWalletInstalled) {
              setState(() => _choosingWallet = true);
              return;
            }
            try {
              await walletCubit.reconnect();
            } catch (_) {
              // Rejected: the button stays.
            }
          },
        );
      case ArNSWalletStatus.connected:
        return ModalAction(
          title: _commitLabel(context, state),
          isEnable: ready,
          action: cubit.commit,
        );
    }
  }

  String _commitLabel(BuildContext context, ArNSNameDialogState state) {
    final strings = appLocalizationsOf(context);
    return switch (state.mode) {
      ArNSNameDialogMode.nameItem =>
        state.changesName ? strings.arnsChangeName : strings.arnsAddName,
      ArNSNameDialogMode.pointRecord ||
      ArNSNameDialogMode.cacheTime =>
        strings.arnsSave,
      ArNSNameDialogMode.remove => strings.arnsRemoveName,
    };
  }

  String _title(BuildContext context, ArNSNameDialogState state) {
    final strings = appLocalizationsOf(context);
    if (state.stage == ArNSDialogStage.failed) {
      return switch (state.failure?.kind) {
        ArNSFailureKind.insufficientCredits => strings.arnsNotEnoughCredits,
        ArNSFailureKind.lostAfterCreate => strings.arnsCheckYourNamesTitle,
        _ => strings.arnsChangeNotMade,
      };
    }
    if (state.stage == ArNSDialogStage.done) {
      return state.mode == ArNSNameDialogMode.remove
          ? strings.arnsNameRemoved
          : strings.arnsNameSaved;
    }
    return switch (state.mode) {
      ArNSNameDialogMode.nameItem =>
        state.changesName ? strings.arnsChangeName : strings.arnsAddName,
      ArNSNameDialogMode.pointRecord => strings.arnsChangeWhatItPointsTo,
      ArNSNameDialogMode.cacheTime => strings.arnsCacheTime,
      ArNSNameDialogMode.remove => strings.arnsRemoveName,
    };
  }
}

class _ChooseContent extends StatelessWidget {
  const _ChooseContent({
    required this.state,
    required this.wallet,
    required this.choosingWallet,
    required this.changingWallet,
    required this.onChangeWallet,
    required this.onLinked,
  });

  final ArNSNameDialogState state;
  final ArNSWalletState wallet;
  final bool choosingWallet;
  final bool changingWallet;
  final VoidCallback onChangeWallet;
  final VoidCallback onLinked;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<ArNSNameDialogCubit>();
    final children = <Widget>[];

    switch (state.mode) {
      case ArNSNameDialogMode.nameItem:
        final item = state.item!;
        children.addAll([
          ArNSBodyText(strings.arnsChooseNameFor(item.name)),
          const SizedBox(height: ArDriveSpacing.md),
          _NamePicker(state: state),
          if (state.movesFrom != null) ...[
            const SizedBox(height: ArDriveSpacing.sm),
            ArNSRemovePreviousBox(state: state),
          ],
          const SizedBox(height: ArDriveSpacing.sm),
          _CacheTimeSection(state: state, folded: true),
        ]);
      case ArNSNameDialogMode.pointRecord:
        children.addAll([
          _RecordSummary(state: state),
          const SizedBox(height: ArDriveSpacing.md),
          _ItemPicker(state: state),
          if (AppRouterDelegate.webPagesAreOn(context)) ...[
            const SizedBox(height: ArDriveSpacing.xs),
            ArNSCaption(strings.arnsNameASiteHint),
          ],
          const SizedBox(height: ArDriveSpacing.sm),
          _CacheTimeSection(state: state, folded: true),
        ]);
      case ArNSNameDialogMode.cacheTime:
        children.addAll([
          _RecordSummary(state: state),
          const SizedBox(height: ArDriveSpacing.md),
          _CacheTimeSection(state: state, folded: false),
        ]);
      case ArNSNameDialogMode.remove:
        children.add(
            _RemoveText(state: state, canRemoveMain: cubit.canRemoveMainName));
    }

    final name = state.selectedName;
    if (name != null && state.inGracePeriod) {
      children.addAll([
        const SizedBox(height: ArDriveSpacing.md),
        ArDriveNotice(
          type: ArDriveNoticeType.warning,
          message: strings.arnsRenewInConsole,
          actionLabel: strings.arnsRenew,
          onAction: () => openUrl(url: arnsRenewUrlFor(name.name)),
        ),
      ]);
    } else if (cubit.change != null || state.pricing || state.costFailed) {
      children.addAll([
        const SizedBox(height: ArDriveSpacing.md),
        _CostLine(state: state),
      ]);
    }

    children.addAll(_walletStep(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  List<Widget> _walletStep(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final widgets = <Widget>[];
    switch (wallet.status) {
      case ArNSWalletStatus.unavailable:
      case ArNSWalletStatus.notLinked:
        widgets.addAll([
          const SizedBox(height: ArDriveSpacing.md),
          ArNSCaption(strings.arnsLinkWalletExplainer),
        ]);
      case ArNSWalletStatus.disconnected:
        widgets.addAll([
          const SizedBox(height: ArDriveSpacing.md),
          ArNSCaption(strings.arnsReconnectExplainer),
        ]);
      case ArNSWalletStatus.wrongAccount:
        widgets.addAll([
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            content: ArNSSwitchAccountText(address: wallet.linked!.address),
            actionLabel: strings.arnsChangeArNSWallet,
            onAction: onChangeWallet,
          ),
        ]);
      case ArNSWalletStatus.connected:
        break;
    }
    if (choosingWallet && wallet.status != ArNSWalletStatus.connected ||
        changingWallet) {
      widgets.addAll([
        const SizedBox(height: ArDriveSpacing.sm),
        ArNSWalletChooser(onLinked: onLinked, changing: changingWallet),
      ]);
    }
    return widgets;
  }
}

/// The names, each with its undernames, in the console's simple style.
/// More records than this across all names, and the picker gets a search
/// box.
const arnsPickerSearchFrom = 6;

/// Undernames a name shows before "Show all", with no search typed.
const arnsPickerUndernamesShown = 5;

/// A name in the picker, with the undernames it lists and how many it
/// leaves out until "Show all".
typedef ArNSPickerGroup = ({
  ArNSManagedName name,
  List<ArNSNameRecord> undernames,
  int hidden,
});

/// The picker's names for [query]: a match on a name keeps all of it,
/// otherwise only its matching undernames, and a name with none is left
/// out. With no query, a name not in [expanded] lists its first few
/// undernames and the chosen one.
List<ArNSPickerGroup> arnsPickerGroups(
  List<ArNSManagedName> names, {
  required String query,
  required Set<String> expanded,
  ArNSRecordChoice? choice,
}) {
  final groups = <ArNSPickerGroup>[];
  for (final name in names) {
    final all = name.records.where((r) => !r.isApex).toList();
    if (query.isNotEmpty) {
      if (arnsHostFor(name.name).contains(query)) {
        groups.add((name: name, undernames: all, hidden: 0));
        continue;
      }
      final matches =
          all.where((r) => arnsHostFor(r.literalName).contains(query));
      if (matches.isNotEmpty) {
        groups.add((name: name, undernames: matches.toList(), hidden: 0));
      }
      continue;
    }
    if (expanded.contains(name.name) ||
        all.length <= arnsPickerUndernamesShown) {
      groups.add((name: name, undernames: all, hidden: 0));
      continue;
    }
    final shown = [
      for (final (i, r) in all.indexed)
        if (i < arnsPickerUndernamesShown ||
            (choice != null &&
                choice.name == name.name &&
                choice.undername == r.undername))
          r,
    ];
    groups.add(
        (name: name, undernames: shown, hidden: all.length - shown.length));
  }
  return groups;
}

class _NamePicker extends StatefulWidget {
  const _NamePicker({required this.state, this.belowChoice});

  final ArNSNameDialogState state;

  /// Shown under the chosen row, such as a flow's repoint question.
  final Widget? belowChoice;

  @override
  State<_NamePicker> createState() => _NamePickerState();
}

class _NamePickerState extends State<_NamePicker> {
  String _query = '';

  /// Names showing all their undernames.
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final state = widget.state;
    final records =
        state.names.fold<int>(0, (sum, name) => sum + name.records.length);
    final query = _query.trim().toLowerCase();

    final groups = <Widget>[];
    for (final group in arnsPickerGroups(
      state.names,
      query: query,
      expanded: _expanded,
      choice: state.choice,
    )) {
      final name = group.name;
      groups.addAll([
        _NameGroup(
          name: name,
          undernames: group.undernames,
          showAll: group.hidden == 0
              ? null
              : ArDriveLink(
                  text: strings.arnsShowAllUndernames(
                      group.undernames.length + group.hidden),
                  isAction: true,
                  onTap: () => setState(() => _expanded.add(name.name)),
                ),
          state: state,
          belowChoice: widget.belowChoice,
        ),
        const SizedBox(height: ArDriveSpacing.xs),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArNSCaption(strings.arnsUndernameExplainer),
        const SizedBox(height: ArDriveSpacing.sm),
        if (records > arnsPickerSearchFrom) ...[
          ArDriveTextFieldNew(
            hintText: strings.arnsFindAName,
            prefixIcon: const Icon(Icons.search, size: 20),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: ArDriveSpacing.sm),
        ],
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
            child: ArNSCaption(strings.arnsNoNamesMatch),
          )
        else
          ...groups,
      ],
    );
  }
}

class _NameGroup extends StatelessWidget {
  const _NameGroup({
    required this.name,
    required this.undernames,
    required this.state,
    this.showAll,
    this.belowChoice,
  });

  final ArNSManagedName name;

  /// The undernames to list: all of them, the first few, or a search's.
  final List<ArNSNameRecord> undernames;

  /// "Show all", when some undernames are left out.
  final Widget? showAll;

  final ArNSNameDialogState state;
  final Widget? belowChoice;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cubit = context.read<ArNSNameDialogCubit>();
    final choice = state.choice;
    final apex = name.apex;
    final creating = state.newUndernameFor == name.name;
    final blocked = name.isInGracePeriod(state.now ?? DateTime.now());

    bool isChosen(String undername) =>
        choice != null &&
        !choice.isNew &&
        choice.name == name.name &&
        choice.undername == undername;

    final shape = BorderRadius.circular(ArDriveRadius.md);
    return Container(
      decoration: BoxDecoration(borderRadius: shape),
      // In front, so a highlighted row never paints over the edge.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: colors.strokeLow),
        borderRadius: shape,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ArNSChoiceRow(
            selected: isChosen(arnsApex),
            enabled: !blocked,
            title: arnsHostFor(name.name),
            emphasized: true,
            subtitle: _pointsTo(context, apex),
            subtitleId: apex == null ? null : shortenId(apex.transactionId),
            tag: name.role == ArNSRole.controller
                ? strings.arnsController
                : null,
            onTap: () => cubit.choose(name.name, arnsApex),
          ),
          if (isChosen(arnsApex)) ..._below(),
          for (final record in undernames) ...[
            ArNSChoiceRow(
              selected: isChosen(record.undername),
              enabled: !blocked,
              indent: true,
              title: arnsHostFor(record.literalName),
              subtitle: _pointsTo(context, record),
              subtitleId: shortenId(record.transactionId),
              onTap: () => cubit.choose(name.name, record.undername),
            ),
            if (isChosen(record.undername)) ..._below(),
          ],
          if (showAll != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ArDriveSpacing.md + 28,
                ArDriveSpacing.xs,
                ArDriveSpacing.md,
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: showAll,
              ),
            ),
          if (creating)
            _NewUndernameField(name: name, state: state)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ArDriveSpacing.md + 28,
                ArDriveSpacing.xs,
                ArDriveSpacing.md,
                ArDriveSpacing.sm,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ArDriveSpacing.sm,
                runSpacing: ArDriveSpacing.xxs,
                children: [
                  if (name.hasFreeUndername && !blocked)
                    ArDriveLink(
                      text: strings.arnsNewUndername,
                      isAction: true,
                      onTap: () => cubit.startNewUndername(name.name),
                    ),
                  ArNSCaption(
                    name.hasFreeUndername
                        ? strings.arnsUndernamesUsed(
                            name.undernamesUsed, name.undernameLimit)
                        : strings.arnsAllUndernamesUsed(name.undernameLimit),
                  ),
                  if (!name.hasFreeUndername)
                    ArDriveLink(
                      text: strings.arnsGetMoreInConsole,
                      external: true,
                      onTap: () => openUrl(url: arnsGetNameUrl),
                    ),
                ],
              ),
            ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ArDriveSpacing.md,
                0,
                ArDriveSpacing.md,
                ArDriveSpacing.sm,
              ),
              child: ArNSCaption(strings.arnsRenewInConsole),
            ),
        ],
      ),
    );
  }

  List<Widget> _below() => [
        if (belowChoice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ArDriveSpacing.md,
              ArDriveSpacing.xxs,
              ArDriveSpacing.md,
              ArDriveSpacing.xs,
            ),
            child: belowChoice,
          ),
      ];

  String? _pointsTo(BuildContext context, ArNSNameRecord? record) {
    if (record == null) return null;
    return arnsPointsToLabel(context, record,
        placeholder: state.placeholderTxId);
  }
}

class _NewUndernameField extends StatefulWidget {
  const _NewUndernameField({required this.name, required this.state});

  final ArNSManagedName name;
  final ArNSNameDialogState state;

  @override
  State<_NewUndernameField> createState() => _NewUndernameFieldState();
}

class _NewUndernameFieldState extends State<_NewUndernameField> {
  late final _controller =
      TextEditingController(text: widget.state.newUndername);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final state = widget.state;
    final text = state.newUndername.trim();
    final problem = text.isEmpty ? null : state.newUndernameProblem;
    final error = state.newUndernameTaken
        ? strings.arnsUndernameTaken
        : switch (problem) {
            null => null,
            UndernameProblem.empty => null,
            UndernameProblem.invalid => strings.arnsUndernameInvalid,
            UndernameProblem.tooLong => strings.arnsUndernameTooLong,
            UndernameProblem.labelTooLong => strings.arnsUndernameLabelTooLong,
          };

    return Container(
      color: state.choice?.isNew == true ? colors.containerL1 : null,
      padding: const EdgeInsets.fromLTRB(
        ArDriveSpacing.md,
        ArDriveSpacing.xs,
        ArDriveSpacing.md,
        ArDriveSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.arnsNewUndername,
            style: typography.paragraphSmall(
              color: colors.textMid,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: ArDriveTextFieldNew(
                  controller: _controller,
                  autofocus: true,
                  hintText: strings.arnsUndernameHint,
                  autocorrect: false,
                  showErrorMessage: false,
                  onChanged: (value) => context
                      .read<ArNSNameDialogCubit>()
                      .editNewUndername(value),
                ),
              ),
              const SizedBox(width: ArDriveSpacing.xs),
              Flexible(
                child: Text(
                  '_${arnsHostFor(widget.name.name)}',
                  overflow: TextOverflow.ellipsis,
                  style: typography.paragraphNormal(color: colors.textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: ArDriveSpacing.xxs),
          Text(
            error ?? strings.arnsUndernameRule,
            style: typography.paragraphSmall(
              color: error != null ? colors.statusErrorFg : colors.textLow,
            ),
          ),
        ],
      ),
    );
  }
}

/// For the Names page: the record being changed and where it points.
class _RecordSummary extends StatelessWidget {
  const _RecordSummary({required this.state});

  final ArNSNameDialogState state;

  @override
  Widget build(BuildContext context) {
    final record = state.selectedRecord;
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    if (record == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          arnsHostFor(record.literalName),
          style: typography.paragraphLarge(
            color: colors.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
        ),
        const SizedBox(height: ArDriveSpacing.xxs),
        ArNSPointsTo(record: record, placeholder: state.placeholderTxId),
      ],
    );
  }
}

/// For the Names page: the ArDrive item a record will point at.
class _ItemPicker extends StatelessWidget {
  const _ItemPicker({required this.state});

  final ArNSNameDialogState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<ArNSNameDialogCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArDriveTextFieldNew(
          hintText: strings.arnsSearchItems,
          prefixIcon: const Icon(Icons.search, size: 20),
          onChanged: cubit.searchItems,
        ),
        const SizedBox(height: ArDriveSpacing.xs),
        if (state.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
            child: ArNSCaption(strings.arnsNoItemsToName),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final item in state.items)
                  ArNSChoiceRow(
                    selected: state.item == item,
                    title: item.name,
                    subtitle: item.isPublication
                        ? strings.arnsPublication
                        : item.isManifest
                            ? strings.arnsDeployment
                            : null,
                    leadingIcon: item.isPublication
                        ? ArDriveIconsData.publish_to_web
                        : item.isManifest
                            ? Icons.web_outlined
                            : Icons.insert_drive_file_outlined,
                    onTap: () => cubit.pickItem(item),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Cache time, folded under Advanced in the name dialog (Q8, Q16).
class _CacheTimeSection extends StatefulWidget {
  const _CacheTimeSection({required this.state, required this.folded});

  final ArNSNameDialogState state;
  final bool folded;

  @override
  State<_CacheTimeSection> createState() => _CacheTimeSectionState();
}

class _CacheTimeSectionState extends State<_CacheTimeSection> {
  late bool _open = !widget.folded;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final picker = ArNSCacheTimePicker(
      value: widget.state.cacheTime,
      onChanged: context.read<ArNSNameDialogCubit>().setCacheTime,
    );
    if (!widget.folded) return picker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            borderRadius: BorderRadius.circular(ArDriveRadius.sm),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
              child: Row(
                children: [
                  Text(
                    strings.arnsAdvanced,
                    style: typography.paragraphNormal(
                      color: colors.textMid,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  const SizedBox(width: ArDriveSpacing.xxs),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colors.iconMid,
                  ),
                  if (!_open) ...[
                    const SizedBox(width: ArDriveSpacing.xs),
                    Flexible(
                      child: ArNSCaption(
                        strings.arnsCacheTimeIs(
                          arnsCacheTimeLabel(context, widget.state.cacheTime),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: ArDriveSpacing.xs),
          picker,
        ],
      ],
    );
  }
}

class _CostLine extends StatelessWidget {
  const _CostLine({required this.state, this.inFlow = false});

  final ArNSNameDialogState state;

  /// Inside a flow's own dialog: top-up opens over it rather than closing
  /// it.
  final bool inFlow;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final cubit = context.read<ArNSNameDialogCubit>();
    final cost = state.cost;
    final children = <Widget>[];

    if (state.costFailed) {
      children.add(ArDriveNotice(
        type: ArDriveNoticeType.error,
        message: strings.arnsCostCouldNotBeRead,
        actionLabel: strings.tryAgain,
        onAction: cubit.retryPrice,
      ));
    } else if (cost == null || state.pricing) {
      children.add(ArNSWaitingLine(text: strings.arnsWorkingOutCost));
    } else {
      final credits = formatArNSCredits(cost.credits);
      final value = cost.paidInSol
          ? (cost.credits > BigInt.zero
              ? strings.arnsCostSolAndCredits(
                  formatSol(cost.solLamports!), credits)
              : strings.arnsCostSol(formatSol(cost.solLamports!)))
          : strings.arnsCostCredits(credits);
      // A managed name's fee is said once, with its amount (Q23).
      children.add(ArNSCostRow(
        label: strings.arnsCost,
        value: value,
        note: cost.paidInSol
            ? strings.arnsControllerPaysSol
            : cost.metadataWrites > 0
                ? (state.removesPrevious
                    ? strings.arnsCostNoteMove
                    : strings.arnsCostNote)
                : null,
      ));
      if (state.insufficientCredits) {
        children.addAll([
          const SizedBox(height: ArDriveSpacing.sm),
          ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: strings.arnsNotEnoughCreditsBody,
            actionLabel: strings.arnsTopUp,
            onAction: () {
              if (!inFlow) Navigator.of(context).pop();
              showTurboTopupModal(context);
            },
          ),
        ]);
      }
      if (state.insufficientSol) {
        children.addAll([
          const SizedBox(height: ArDriveSpacing.sm),
          ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: strings.arnsNotEnoughSol,
          ),
        ]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _RemoveText extends StatelessWidget {
  const _RemoveText({required this.state, required this.canRemoveMain});

  final ArNSNameDialogState state;
  final bool canRemoveMain;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final record = state.selectedRecord;
    if (record == null) return const SizedBox.shrink();
    final host = arnsHostFor(record.literalName);
    if (record.isApex && !canRemoveMain) {
      return ArDriveNotice(
        type: ArDriveNoticeType.info,
        message: strings.arnsMainNameRemovalUnavailable,
      );
    }
    return ArNSBodyText(
      record.isApex
          ? strings.arnsRemoveMainNameBody(host)
          : strings.arnsRemoveUndernameBody(host),
    );
  }
}

/// "blog_acme.ar.io points to *Last year's site*. Point it here instead?"
/// (Q11), in the name dialog and in a flow's name step.
class ArNSRepointQuestion extends StatelessWidget {
  const ArNSRepointQuestion({super.key, required this.record});

  final ArNSNameRecord record;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final target = record.target;
    final host = arnsHostFor(record.literalName);
    final base = typography.paragraphNormal(color: colors.textHigh);

    if (target is ArNSFileItem) {
      return Text.rich(
        TextSpan(style: base, children: [
          TextSpan(text: strings.arnsRepointBefore(host)),
          TextSpan(
            text: target.name,
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
          TextSpan(text: strings.arnsRepointAfter),
        ]),
      );
    }
    return Text(strings.arnsRepointElsewhere(host), style: base);
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final ArNSNameDialogState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final text = switch (state.step) {
      ArNSCommitStep.approve => strings.arnsApproveInWallet,
      ArNSCommitStep.working => strings.arnsMakingTheChange,
      ArNSCommitStep.approveTransaction => strings.arnsApproveSecondPrompt,
      ArNSCommitStep.updatingDetails => strings.arnsUpdatingDetails,
      null => strings.arnsMakingTheChange,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArNSBodyText(text),
        const SizedBox(height: ArDriveSpacing.md),
        ArDriveLinearProgress(semanticsLabel: text),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state});

  final ArNSNameDialogState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final literal = state.choice?.literalName;
    if (literal == null) return const SizedBox.shrink();
    final removed = state.mode == ArNSNameDialogMode.remove;
    final undernameRemoved = removed && state.choice?.undername != arnsApex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArNSBodyText(
          removed
              ? (undernameRemoved
                  ? strings.arnsRemovedUndernameDone(arnsHostFor(literal))
                  : strings.arnsRemovedMainNameDone(arnsHostFor(literal)))
              : strings.arnsLiveWithin(
                  arnsTtlLabel(
                    context,
                    state.liveWithinSeconds ?? state.cacheTime.seconds,
                  ),
                ),
        ),
        if (!removed) ...[
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveCopyField(
            label: strings.arnsName,
            text: arnsUrlFor(literal),
            copyLabel: strings.copyLink,
            copiedLabel: strings.copied,
            copyFailedLabel: strings.couldNotCopy,
          ),
        ],
        if (state.previousRemovalFailed && state.previousRecord != null) ...[
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: strings.arnsOldNameNotRemoved(
              arnsHostFor(state.previousRecord!.literalName),
            ),
          ),
        ],
        if (state.metadataFailed) ...[
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: strings.arnsDetailsNotUpdated,
          ),
        ],
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state});

  final ArNSNameDialogState state;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final failure = state.failure;
    final text = switch (failure?.kind) {
      ArNSFailureKind.insufficientCredits => strings.arnsInsufficientCredits,
      ArNSFailureKind.rejected => strings.arnsRejected,
      ArNSFailureKind.expired => failure!.refunded
          ? strings.arnsExpiredRefunded
          : strings.arnsExpiredRefunding,
      ArNSFailureKind.lostAfterCreate => strings.arnsLostAfterCreate,
      ArNSFailureKind.wrongAccount => null,
      ArNSFailureKind.failed || null => strings.arnsFailedNothingCharged,
    };
    if (text == null) {
      final address = context.read<ArNSWalletCubit>().state.linked?.address;
      return ArNSSwitchAccountText(address: address ?? '');
    }
    return ArNSBodyText(text);
  }
}

/// Change name moves the name: "Also remove blog_acme.ar.io", on by default.
class ArNSRemovePreviousBox extends StatelessWidget {
  const ArNSRemovePreviousBox({super.key, required this.state});

  final ArNSNameDialogState state;

  @override
  Widget build(BuildContext context) {
    final previous = state.movesFrom!;
    return ArDriveCheckBox(
      key: ValueKey('remove-${previous.literalName}'),
      checked: state.removePrevious,
      title: appLocalizationsOf(context)
          .arnsAlsoRemove(arnsHostFor(previous.literalName)),
      titleStyle: ArDriveTypographyNew.of(context).paragraphNormal(
        color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
      ),
      onChange: (value) =>
          context.read<ArNSNameDialogCubit>().setRemovePrevious(value),
    );
  }
}

/// The executor every name change runs through, remembering each Turbo
/// action's nonce for the signed-in profile so a reload can resume it.
ArNSChangeExecutor arnsChangeExecutor(BuildContext context, ArioSDK arioSDK) {
  ArNSPendingActionStore? pending;
  try {
    pending = context.read<ArNSPendingActionStore>();
  } on ProviderNotFoundException {
    pending = null;
  }
  final walletCubit = context.read<ArNSWalletCubit>();
  return ArNSChangeExecutor(
    client: context.read<TurboArNSActionClient>(),
    arioSDK: arioSDK,
    pending: pending,
    profileAddress: () => walletCubit.state.profileAddress,
  );
}

/// Whether a flow offers names: the flag, outside a publication, with the
/// names cubit provided. Returns the flow's name cubit, or null.
ArNSFlowNameCubit? createArNSFlowNameCubit(
  BuildContext context, {
  List<ArNSNameRecord> following = const [],
  bool writesHint = true,
}) {
  if (!arnsFlowNamesOn(context)) return null;
  final auth = context.read<ArDriveAuth>();
  final paymentService = context.read<PaymentService>();
  final arioSDK = ArioSDKFactory().create();
  final driveDao = context.read<DriveDao>();
  final arnsDao = context.read<Database>().aRNSDao;
  return ArNSFlowNameCubit(
    namesCubit: context.read<ArNSNamesCubit>(),
    walletCubit: context.read<ArNSWalletCubit>(),
    actionClient: context.read<TurboArNSActionClient>(),
    executor: arnsChangeExecutor(context, arioSDK),
    arioSDK: arioSDK,
    metadataWriter: DriveDaoArNSFileMetadataWriter(
      driveDao: driveDao,
      arweave: context.read<ArweaveService>(),
      turboUploadService: context.read<TurboUploadService>(),
      paymentService: paymentService,
      auth: auth,
    ),
    paymentSource: ArDriveArNSPaymentSource(
      auth: auth,
      paymentService: paymentService,
    ),
    following: following,
    writesHint: writesHint,
    placeholderTxId: context.read<ConfigService>().config.arnsPlaceholderTxId,
    resolveItem: (dataTxId) async {
      final rows =
          await arnsDao.fileRevisionsForDataTxIds(txIds: [dataTxId]).get();
      for (final row in rows) {
        if (row.dataTxId == row.latestDataTxId) {
          return ArNSNameableItem(
            fileId: row.fileId,
            driveId: row.driveId,
            name: row.name,
            dataTxId: dataTxId,
            isManifest: row.dataContentType == ContentType.manifest,
          );
        }
      }
      return null;
    },
  )..load();
}

/// Names on, outside a publication, with the names cubit provided.
bool arnsFlowNamesOn(BuildContext context) {
  if (PublicationMode.isOn) return false;
  try {
    if (!context.read<ConfigService>().config.enableArNS) return false;
    context.read<ArNSNamesCubit>();
    context.read<ArNSWalletCubit>();
    return true;
  } on ProviderNotFoundException {
    return false;
  }
}

/// The names on the item a new version replaces, from the owner's names.
List<ArNSNameRecord> arnsNamesOnVersion(BuildContext context, String? txId) {
  if (txId == null || !arnsFlowNamesOn(context)) return const [];
  return context.read<ArNSNamesCubit>().state.recordsFor(txId);
}

/// The name step inside a flow: the names moving to the new version, with a
/// box to leave them, and an optional new name, folded away (docs/NAMES.md,
/// "Name an item", "New versions").
class ArNSFlowNameSection extends StatefulWidget {
  const ArNSFlowNameSection({
    super.key,
    required this.cubit,
    this.initiallyOpen = false,
  });

  final ArNSFlowNameCubit cubit;

  /// Folded by default: most flows add no name.
  final bool initiallyOpen;

  @override
  State<ArNSFlowNameSection> createState() => _ArNSFlowNameSectionState();
}

class _ArNSFlowNameSectionState extends State<ArNSFlowNameSection> {
  late bool _open = widget.initiallyOpen;
  bool _choosingWallet = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ArNSNameDialogCubit>.value(
      value: widget.cubit,
      child: BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
        builder: (context, wallet) =>
            BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
          builder: (context, state) => _build(context, state, wallet),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ArNSNameDialogState state,
    ArNSWalletState wallet,
  ) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final cubit = widget.cubit;
    final children = <Widget>[];

    if (state.following.isNotEmpty) {
      for (final record in state.following) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
          child: Row(
            children: [
              Icon(arnsNameIcon, size: 16, color: colors.iconMid),
              const SizedBox(width: ArDriveSpacing.xs),
              Expanded(
                child: ArNSBodyText(!state.moving.contains(record)
                    ? strings
                        .arnsStaysOnOldVersion(arnsHostFor(record.literalName))
                    : strings.arnsMovesToNewVersion(
                        arnsHostFor(record.literalName))),
              ),
            ],
          ),
        ));
      }
      children.add(ArDriveCheckBox(
        checked: state.leaveOnOld,
        title: strings.arnsLeaveOnOldVersion,
        titleStyle: typography.paragraphNormal(color: colors.textHigh),
        onChange: cubit.setLeaveOnOld,
      ));
      children.add(const SizedBox(height: ArDriveSpacing.sm));
    }

    children.add(Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xs),
          child: Row(
            children: [
              Icon(arnsNameIcon, size: 18, color: colors.iconMid),
              const SizedBox(width: ArDriveSpacing.xs),
              Text(
                strings.arnsAddName,
                style: typography.paragraphNormal(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              const SizedBox(width: ArDriveSpacing.xs),
              Expanded(
                child: ArNSCaption(state.choice?.undername.isNotEmpty == true
                    ? arnsHostFor(state.choice!.literalName)
                    : strings.arnsOptional),
              ),
              Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: colors.iconMid,
              ),
            ],
          ),
        ),
      ),
    ));

    // Under the chosen name while the step is open, under the step's
    // heading while it is folded: the flow's button waits for the answer.
    final repointing = cubit.repointing;
    final repointQuestion = repointing == null
        ? null
        : ArDriveNotice(
            type: ArDriveNoticeType.warning,
            content: ArNSRepointQuestion(record: repointing),
            actionLabel: strings.arnsPointItHere,
            onAction: cubit.confirmRepoint,
          );
    if (!_open && repointQuestion != null) {
      children.addAll([
        const SizedBox(height: ArDriveSpacing.xs),
        repointQuestion,
      ]);
    }

    if (_open) {
      children.add(const SizedBox(height: ArDriveSpacing.xs));
      switch (state.stage) {
        case ArNSDialogStage.loading:
          children.add(ArNSWaitingLine(text: strings.arnsReadingNames));
        case ArNSDialogStage.needsWallet:
          children.addAll([
            ArNSCaption(strings.arnsLinkWalletExplainer),
            const SizedBox(height: ArDriveSpacing.sm),
            const ArNSWalletChooser(),
          ]);
        case ArNSDialogStage.noNames:
          children.add(Wrap(
            spacing: ArDriveSpacing.xs,
            children: [
              ArNSCaption(strings.arnsNoNamesTitle),
              ArDriveLink(
                text: strings.arnsGetANameInConsole,
                external: true,
                onTap: () => openUrl(url: arnsGetNameUrl),
              ),
            ],
          ));
        case ArNSDialogStage.loadFailed:
          children.add(ArNSCaption(strings.arnsNamesCouldNotBeRead));
        default:
          children.addAll([
            _NamePicker(state: state, belowChoice: repointQuestion),
            if (state.choice != null) ...[
              const SizedBox(height: ArDriveSpacing.xs),
              ArDriveLink(
                text: strings.arnsNoNameThisTime,
                isAction: true,
                onTap: cubit.clearChoice,
              ),
            ],
            const SizedBox(height: ArDriveSpacing.sm),
            _CacheTimeSection(state: state, folded: true),
          ]);
      }
    }

    if (cubit.hasWork) {
      children.addAll([
        const SizedBox(height: ArDriveSpacing.sm),
        _CostLine(state: state, inFlow: true),
      ]);
      if (wallet.status != ArNSWalletStatus.connected) {
        children.addAll([
          const SizedBox(height: ArDriveSpacing.sm),
          if (wallet.status == ArNSWalletStatus.wrongAccount)
            ArNSSwitchAccountText(address: wallet.linked!.address)
          else
            ArNSCaption(wallet.linked == null
                ? strings.arnsLinkWalletExplainer
                : strings.arnsReconnectExplainer),
          const SizedBox(height: ArDriveSpacing.xs),
          if (_choosingWallet || wallet.noWalletInstalled)
            ArNSWalletChooser(
              onLinked: () => setState(() => _choosingWallet = false),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: ArDriveButtonNew(
                text: wallet.linked == null
                    ? strings.arnsLinkSolanaWallet
                    : strings.arnsReconnectSolanaWallet,
                typography: typography,
                size: ArDriveButtonSize.compact,
                variant: ButtonVariant.secondary,
                onPressed: () async {
                  final walletName = wallet.linked?.walletName;
                  if (walletName == null) {
                    setState(() => _choosingWallet = true);
                    return;
                  }
                  try {
                    await context.read<ArNSWalletCubit>().reconnect();
                  } catch (_) {
                    // Rejected: the button stays.
                  }
                },
              ),
            ),
        ]);
      }
    }

    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: colors.strokeLow),
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// A flow's names afterwards, on its success screen.
class ArNSFlowNameResult extends StatelessWidget {
  const ArNSFlowNameResult({super.key, required this.outcome});

  final ArNSFlowOutcome outcome;

  @override
  Widget build(BuildContext context) {
    if (outcome.isEmpty) return const SizedBox.shrink();
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Each name wraps in its own line, and the caption follows them:
        // beside a real name it had no room left and stood a letter wide.
        for (final literal in outcome.live)
          Padding(
            padding: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(arnsNameIcon, size: 16, color: colors.iconMid),
                ),
                const SizedBox(width: ArDriveSpacing.xs),
                Flexible(
                  child: ArDriveLink(
                    text: arnsHostFor(literal),
                    external: true,
                    onTap: () => openUrl(url: arnsUrlFor(literal)),
                  ),
                ),
              ],
            ),
          ),
        if (outcome.live.isNotEmpty)
          ArNSCaption(strings.arnsLiveWithin(
            arnsTtlLabel(context, outcome.liveWithinSeconds),
          )),
        if (outcome.failed.isNotEmpty) ...[
          const SizedBox(height: ArDriveSpacing.xs),
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: strings.arnsFlowNameNotSet(
              outcome.failed.map(arnsHostFor).join(', '),
            ),
          ),
        ],
      ],
    );
  }
}
