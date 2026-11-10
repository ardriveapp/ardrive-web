import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the app's state machines explicit where the compiler can't.
///
/// Bloc drops a state equal to the one before it, and a cubit that casts its
/// state throws when an event lands after the state has moved on. Both bugs
/// are invisible until a user hits them: a "Canceling..." that never shows, a
/// payment whose success screen never comes. The rules, in CLAUDE.md under
/// "State machines":
///
/// 1. A state's equality covers every field, or says why not.
/// 2. A transition checks the state it starts from: `if (state case final X
///    s)`, not `state as X`.
/// 3. A flow's data travels in its state, not in fields of the cubit.
/// 4. A family of states is `sealed`, so a `switch` over it is exhaustive.
///
/// Rules 1, 2 and 4 are scanned for here; rule 3 is for review.
///
/// Code from before this test is listed in the `_legacy...` tables with a
/// count. A count may only go down: a file over its count fails, and a file
/// under it fails too until the table is lowered, so the tables stay honest.
/// A deliberate exception goes in an `_...Exceptions` table with its reason.
void main() {
  final sources = _sources();

  test('transitions check their state instead of casting it', () {
    expect(
      _overCount(sources, _stateCast, _legacyCasts),
      isEmpty,
      reason: 'Replace `state as X` with `if (state case final X s)` (or a '
          'switch), so an event that lands after the state has moved on does '
          'nothing instead of throwing.',
    );
  });

  test('equality is not switched off with a throwaway key', () {
    expect(
      _overCount(sources, _equalityBust, _legacyEqualityBusts),
      isEmpty,
      reason: 'A state that has to re-emit an equal value carries a field that '
          'changes (a sequence or revision number) and lists it in props.',
    );
  });

  test('props cover every field of a state', () {
    final found = <String>[];
    _classes(sources).forEach((key, info) {
      final allowed = {
        ...?_legacyPropsGaps[key],
        ...?_propsExceptions[key]?.fields,
      };
      final missing = info.missing.where((f) => !allowed.contains(f)).toList();
      if (missing.isNotEmpty) found.add('$key leaves out $missing');
    });
    expect(
      found,
      isEmpty,
      reason: 'Bloc drops a state equal to the last one, so a field missing '
          'from props is a rebuild that never happens. Add it to props, or '
          'list it in _propsExceptions with the reason it must not count.',
    );
  });

  test('families of states are sealed', () {
    final found = <String>[];
    sources.forEach((path, lines) {
      for (final match in _abstractState.allMatches(lines.join('\n'))) {
        final key = '$path ${match.group(1)}';
        if (!_legacyUnsealed.contains(key)) found.add(key);
      }
    });
    expect(
      found,
      isEmpty,
      reason: 'Make the base `sealed class`, so a switch over its states is '
          'exhaustive and adding one is a compile error wherever it is not '
          'handled.',
    );
  });

  test('every exception and legacy count is still needed', () {
    final stale = <String>[
      ..._underCount(sources, _stateCast, _legacyCasts),
      ..._underCount(sources, _equalityBust, _legacyEqualityBusts),
    ];
    final classes = _classes(sources);
    for (final entry in {
      ..._legacyPropsGaps,
      for (final e in _propsExceptions.entries) e.key: e.value.fields,
    }.entries) {
      final missing = classes[entry.key]?.missing ?? const <String>{};
      final unneeded = entry.value.where((f) => !missing.contains(f));
      if (unneeded.isNotEmpty) stale.add('${entry.key} $unneeded');
    }
    final unsealed = {
      for (final e in sources.entries)
        for (final m in _abstractState.allMatches(e.value.join('\n')))
          '${e.key} ${m.group(1)}',
    };
    stale.addAll(_legacyUnsealed.where((key) => !unsealed.contains(key)));
    expect(
      stale,
      isEmpty,
      reason: 'These got better: lower or remove them in the tables.',
    );
  });
}

final _stateCast = RegExp(r'\bstate\s+as\s+[A-Z]');

final _equalityBust =
    RegExp(r'props\s*=>\s*\[\s*UniqueKey\(\)|\bequatableBust\s*:');

final _abstractState = RegExp(
    r'^abstract class (\w+State)\b[^{]*\bextends Equatable',
    multiLine: true);

/// A field that is out of props on purpose, and why.
typedef _Exception = ({Set<String> fields, String reason});

const Map<String, _Exception> _propsExceptions = {
  'lib/sync/domain/cubit/sync_state.dart SyncCompleteWithErrors': (
    fields: {'completedAt'},
    reason: 'the top bar\'s announcement is timed from the moment of '
        'completion, not from each rebuild',
  ),
  'lib/sync/domain/cubit/sync_state.dart SyncComplete': (
    fields: {'completedAt'},
    reason: 'as SyncCompleteWithErrors; `sequence` tells two runs apart',
  ),
};

// --- Code from before this test. Counts only go down. ---

const _legacyCasts = <String, int>{
  'lib/blocs/bulk_import/bulk_import_bloc.dart': 1,
  'lib/blocs/create_manifest/create_manifest_cubit.dart': 11,
  'lib/blocs/create_snapshot/create_snapshot_cubit.dart': 10,
  'lib/blocs/drive_create/drive_create_cubit.dart': 2,
  'lib/blocs/drive_detail/drive_detail_cubit.dart': 10,
  'lib/blocs/drive_rename/drive_rename_cubit.dart': 1,
  'lib/blocs/drives/drives_cubit.dart': 2,
  'lib/blocs/folder_create/folder_create_cubit.dart': 1,
  'lib/blocs/fs_entry_license/fs_entry_license_bloc.dart': 2,
  'lib/blocs/fs_entry_move/fs_entry_move_bloc.dart': 1,
  'lib/blocs/fs_entry_rename/fs_entry_rename_cubit.dart': 1,
  'lib/blocs/ghost_fixer/ghost_fixer_cubit.dart': 4,
  'lib/blocs/hide/hide_bloc.dart': 5,
  'lib/blocs/pin_file/pin_file_bloc.dart': 5,
  'lib/blocs/profile/profile_cubit.dart': 1,
  'lib/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart': 2,
  'lib/blocs/upload/upload_cubit.dart': 20,
  'lib/components/details_panel.dart': 1,
  'lib/components/pin_file_dialog.dart': 1,
  'lib/components/profile_card.dart': 1,
  'lib/components/upload_form.dart': 2,
  'lib/drive_explorer/multi_thumbnail_creation/bloc/multi_thumbnail_creation_bloc.dart':
      1,
  'lib/drive_state/presentation/drive_state_creation_modal.dart': 1,
  'lib/pages/drive_detail/components/drive_detail_folder_empty_card.dart': 1,
  'lib/pages/drive_detail/components/drive_explorer_item_tile.dart': 1,
  'lib/pages/drive_detail/components/fs_entry_preview_widget.dart': 11,
  'lib/pages/drive_detail/drive_detail_page.dart': 1,
  'lib/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart':
      1,
  'lib/sync/domain/cubit/sync_cubit.dart': 1,
  'lib/sync/presentation/sync_failure_toast.dart': 1,
  'lib/turbo/topup/blocs/payment_form/payment_form_bloc.dart': 3,
  'lib/turbo/topup/blocs/topup_estimation_bloc.dart': 1,
  'lib/turbo/topup/blocs/unified_topup/unified_topup_bloc.dart': 11,
  'lib/turbo/topup/views/topup_review_view.dart': 1,
  'lib/turbo/topup/views/unified/inline_crypto_payment.dart': 5,
};

const _legacyEqualityBusts = <String, int>{
  'lib/blocs/upload/upload_cubit.dart': 4,
  'lib/blocs/upload/upload_state.dart': 2,
};

const _legacyPropsGaps = <String, Set<String>>{
  'lib/arns/presentation/name_dialog/arns_name_dialog_state.dart ArNSNameDialogState':
      {'placeholderTxId'},
  'lib/authentication/login/blocs/login_state.dart CreateNewPassword': {
    'derivedEthWallet',
    'sourceWalletAddress'
  },
  'lib/authentication/login/blocs/login_state.dart GatewayLoginFailure': {
    'error',
    'gatewayUrl'
  },
  'lib/authentication/login/blocs/login_state.dart LoginDownloadGeneratedWallet':
      {'mnemonic', 'wallet'},
  'lib/authentication/login/blocs/login_state.dart LoginFailure': {'error'},
  'lib/authentication/login/blocs/login_state.dart LoginShowBlockingDialog': {
    'message'
  },
  'lib/authentication/login/blocs/login_state.dart LoginSuccess': {'user'},
  'lib/authentication/login/blocs/login_state.dart LoginUnknownFailure': {
    'error'
  },
  'lib/authentication/login/blocs/login_state.dart PromptPassword': {
    'alreadyLoggedIn',
    'derivedEthWallet',
    'sourceWalletAddress'
  },
  'lib/blocs/create_manifest/create_manifest_state.dart CreateManifestSuccess':
      {'dataTxId', 'parentFolder'},
  'lib/blocs/create_manifest/create_manifest_state.dart CreateManifestUploadReview':
      {'canUpload'},
  'lib/blocs/data_export/data_export_state.dart DataExportSuccess': {
    'bytes',
    'lastModified',
    'mimeType'
  },
  'lib/blocs/drive_detail/drive_detail_state.dart DriveDetailLoadSuccess': {
    'columnVisibility',
    'hasFoldersSelected',
    'pathSegments'
  },
  'lib/blocs/file_download/file_download_state.dart FileDownloadFailure': {
    'reason'
  },
  'lib/blocs/file_download/file_download_state.dart FileDownloadSuccess': {
    'bytes',
    'lastModified',
    'mimeType'
  },
  'lib/blocs/file_download/file_download_state.dart FileDownloadWithProgress': {
    'contentType',
    'fileSize'
  },
  'lib/blocs/folder_create/folder_create_state.dart FolderCreateNameAlreadyExists':
      {'folderName'},
  'lib/blocs/fs_entry_info/fs_entry_info_state.dart FsEntryDriveInfoSuccess': {
    'drive'
  },
  'lib/blocs/fs_entry_info/fs_entry_info_state.dart FsEntryInfoSuccess': {
    'entry'
  },
  'lib/blocs/fs_entry_move/fs_entry_move_state.dart FsEntryMoveNameConflict': {
    'allItems'
  },
  'lib/blocs/fs_entry_rename/fs_entry_rename_state.dart EntityAlreadyExists': {
    'entityName'
  },
  'lib/blocs/fs_entry_rename/fs_entry_rename_state.dart UpdatingEntityExtension':
      {'entityName', 'newExtension', 'previousExtension'},
  'lib/blocs/hide/hide_state.dart ConfirmingHideState': {
    'cost',
    'dataItems',
    'hideEntitySettings'
  },
  'lib/blocs/pin_file/pin_file_state.dart PinFileFieldsValid': {'privacy'},
  'lib/blocs/pin_file/pin_file_state.dart PinFileFieldsValidationError': {
    'cancelled',
    'doesDataTransactionExist',
    'isArFsEntityPublic',
    'isArFsEntityValid',
    'networkError'
  },
  'lib/blocs/pin_file/pin_file_state.dart PinFileState': {
    'id',
    'idValidation',
    'name',
    'nameValidation'
  },
  'lib/blocs/upload/payment_method/bloc/upload_payment_method_state.dart UploadPaymentMethodLoaded':
      {'canUpload'},
  'lib/blocs/upload/payment_method/bloc/upload_payment_method_state.dart UploadPaymentMethodLoading':
      {'isArConnect'},
  'lib/blocs/upload/upload_state.dart UploadComplete': {
    'dataTxIds',
    'fileIds',
    'numberOfFiles'
  },
  'lib/blocs/upload/upload_state.dart UploadFailure': {'controller'},
  'lib/blocs/upload/upload_state.dart UploadFileConflict': {
    'areAllFilesConflicting',
    'conflictingFileNamesForFailedFiles'
  },
  'lib/blocs/upload/upload_state.dart UploadFileTooLarge': {
    'hasFilesToUpload',
    'isPrivate'
  },
  'lib/blocs/upload/upload_state.dart UploadInProgress': {
    'controller',
    'isCanceling',
    'progress',
    'totalProgress',
    'uploadMethod'
  },
  'lib/blocs/upload/upload_state.dart UploadManifestSelectPaymentMethod': {
    'drive',
    'files',
    'manifestModels',
    'parentFolder'
  },
  'lib/blocs/upload/upload_state.dart UploadPreparationInitialized': {
    'showLoadingFiles'
  },
  'lib/blocs/upload/upload_state.dart UploadReady': {
    'canShowSettings',
    'isArConnect',
    'isDragNDrop',
    'isNextButtonEnabled',
    'manifestFiles',
    'numberOfFiles',
    'params',
    'paymentInfo',
    'selectedManifestSelections',
    'shouldShowCustomManifestCheckbox',
    'showReviewButtonText',
    'showSettings',
    'totalSize',
    'uploadFileAsCustomManifest',
    'uploadIsPublic'
  },
  'lib/blocs/upload/upload_state.dart UploadReadyToPrepare': {'isArConnect'},
  'lib/blocs/upload/upload_state.dart UploadReview': {'readyState'},
  'lib/blocs/upload/upload_state.dart UploadShowingWarning': {
    'uploadPlanForAR',
    'uploadPlanForTurbo'
  },
  'lib/blocs/upload/upload_state.dart UploadingManifests': {
    'completedCount',
    'manifestFiles'
  },
  'lib/gar/presentation/bloc/gar_state.dart GatewayActive': {'gateway'},
  'lib/gar/presentation/bloc/gar_state.dart GatewayChanged': {'gateway'},
  'lib/sharing/folder_selector/folder_selector_state.dart FolderSelectedState':
      {'driveId', 'folder'},
  'lib/sharing/folder_selector/folder_selector_state.dart SelectingFolderState':
      {'isRootFolder', 'parentFolder'},
  'lib/sync/domain/cubit/sync_state.dart SyncFailure': {
    'deep',
    'driveIds',
    'driveName',
    'error',
    'failedAt',
    'kind',
    'singleDriveId',
    'stackTrace',
    'wasDriveListRefresh'
  },
  'lib/turbo/topup/blocs/turbo_topup_flow_state.dart TurboTopupFlowShowingErrorView':
      {'errorType'},
  'lib/turbo/topup/blocs/turbo_topup_flow_state.dart TurboTopupFlowShowingPaymentFormView':
      {'priceEstimate'},
  'lib/turbo/topup/blocs/turbo_topup_flow_state.dart TurboTopupFlowShowingPaymentReviewView':
      {'priceEstimate'},
  'lib/turbo/topup/blocs/turbo_topup_flow_state.dart TurboTopupFlowState': {
    'isMovingForward'
  },
  'lib/user/balance/user_balance_state.dart UserBalanceLoaded': {
    'arBalance',
    'errorFetchingIOTokens',
    'ioTokens'
  },
  'lib/user/name/presentation/bloc/profile_name_state.dart ProfileNameInitial':
      {'walletAddress'},
  'lib/user/name/presentation/bloc/profile_name_state.dart ProfileNameLoadedWithWalletAddress':
      {'walletAddress'},
  'lib/user/name/presentation/bloc/profile_name_state.dart ProfileNameLoading':
      {'walletAddress'},
};

const _legacyUnsealed = <String>{
  'lib/authentication/login/blocs/login_state.dart LoginState',
  'lib/blocs/activity/activity_state.dart ActivityState',
  'lib/blocs/bulk_import/bulk_import_state.dart BulkImportState',
  'lib/blocs/create_manifest/create_manifest_state.dart CreateManifestState',
  'lib/blocs/create_snapshot/create_snapshot_state.dart CreateSnapshotState',
  'lib/blocs/data_export/data_export_state.dart DataExportState',
  'lib/blocs/drive_attach/drive_attach_state.dart DriveAttachState',
  'lib/blocs/drive_create/drive_create_state.dart DriveCreateState',
  'lib/blocs/drive_detail/drive_detail_state.dart DriveDetailState',
  'lib/blocs/drive_rename/drive_rename_state.dart DriveRenameState',
  'lib/blocs/drive_share/drive_share_state.dart DriveShareState',
  'lib/blocs/drives/drives_state.dart DrivesState',
  'lib/blocs/file_download/file_download_state.dart FileDownloadState',
  'lib/blocs/file_share/file_share_state.dart FileShareState',
  'lib/blocs/folder_create/folder_create_state.dart FolderCreateState',
  'lib/blocs/fs_entry_activity/fs_entry_activity_state.dart FsEntryActivityState',
  'lib/blocs/fs_entry_info/fs_entry_info_state.dart FsEntryInfoState',
  'lib/blocs/fs_entry_license/fs_entry_license_state.dart FsEntryLicenseState',
  'lib/blocs/fs_entry_move/fs_entry_move_state.dart FsEntryMoveState',
  'lib/blocs/fs_entry_preview/fs_entry_preview_state.dart FsEntryPreviewState',
  'lib/blocs/fs_entry_rename/fs_entry_rename_state.dart FsEntryRenameState',
  'lib/blocs/fs_entry_snapshots/fs_entry_snapshots_state.dart FsEntrySnapshotsState',
  'lib/blocs/ghost_fixer/ghost_fixer_state.dart GhostFixerState',
  'lib/blocs/hide/hide_state.dart HideState',
  'lib/blocs/keyboard_listener/keyboard_listener_state.dart KeyboardListenerState',
  'lib/blocs/note_create/note_create_state.dart NoteCreateState',
  'lib/blocs/pin_file/pin_file_state.dart PinFileState',
  'lib/blocs/profile/profile_state.dart ProfileState',
  'lib/blocs/profile_add/profile_add_state.dart ProfileAddState',
  'lib/blocs/prompt_to_snapshot/prompt_to_snapshot_state.dart PromptToSnapshotState',
  'lib/blocs/shared_file/shared_file_state.dart SharedFileState',
  'lib/blocs/upload/upload_state.dart UploadState',
  'lib/download/multiple_download_state.dart MultipleDownloadState',
  'lib/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_state.dart DriveStateCreationState',
  'lib/drives_list/presentation/drives_list_state.dart DrivesListState',
  'lib/gar/presentation/bloc/gar_state.dart GarState',
  'lib/pages/raw_transaction_view/raw_transaction_view_state.dart RawTransactionViewState',
  'lib/sync/domain/cubit/sync_state.dart SyncState',
  'lib/theme/theme_switcher_state.dart ThemeSwitcherState',
  'lib/turbo/topup/blocs/crypto_topup/crypto_topup_state.dart CryptoTopupState',
  'lib/turbo/topup/blocs/payment_form/payment_form_state.dart PaymentFormState',
  'lib/turbo/topup/blocs/payment_review/payment_review_state.dart PaymentReviewState',
  'lib/turbo/topup/blocs/topup_estimation_state.dart TopupEstimationState',
  'lib/turbo/topup/blocs/turbo_balance/turbo_balance_state.dart TurboBalanceState',
  'lib/turbo/topup/blocs/turbo_topup_flow_state.dart TurboTopupFlowState',
  'lib/user/download_wallet/bloc/download_wallet_state.dart DownloadWalletState',
};

// --- Scanning ---

/// Each Dart source under lib/, with comments taken out, keyed by its path
/// from the app root. Generated code is left out.
Map<String, List<String>> _sources() {
  final files = <String, List<String>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    final path = entity.path.replaceAll(r'\', '/');
    if (entity is! File ||
        !path.endsWith('.dart') ||
        path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart') ||
        path.startsWith('lib/services/arweave/graphql/')) {
      continue;
    }
    files[path] = entity
        .readAsLinesSync()
        .map((line) => line.replaceFirst(RegExp(r'//.*$'), ''))
        .toList();
  }
  return files;
}

Map<String, int> _counts(Map<String, List<String>> sources, RegExp rule) {
  final counts = <String, int>{};
  sources.forEach((path, lines) {
    final n = rule.allMatches(lines.join('\n')).length;
    if (n > 0) counts[path] = n;
  });
  return counts;
}

List<String> _overCount(
  Map<String, List<String>> sources,
  RegExp rule,
  Map<String, int> legacy,
) =>
    [
      for (final e in _counts(sources, rule).entries)
        if (e.value > (legacy[e.key] ?? 0))
          "'${e.key}': ${e.value}, (allowed ${legacy[e.key] ?? 0})",
    ];

List<String> _underCount(
  Map<String, List<String>> sources,
  RegExp rule,
  Map<String, int> legacy,
) {
  final counts = _counts(sources, rule);
  return [
    for (final e in legacy.entries)
      if ((counts[e.key] ?? 0) < e.value)
        "'${e.key}': ${counts[e.key] ?? 0}, (listed ${e.value})",
  ];
}

class _ClassInfo {
  _ClassInfo(this.missing);

  /// Fields of the class that its props never name.
  final Set<String> missing;
}

final _classHeader = RegExp(
  r'^(?:abstract |sealed |final |base |interface )*class (\w+)\b([^{;]*)\{',
  multiLine: true,
);

/// The names of every state class under lib/ whose equality comes from
/// Equatable, directly or through a superclass.
Set<String> _equatableClasses(Map<String, List<String>> sources) {
  final parents = <String, String?>{};
  final mixesIn = <String>{};
  for (final lines in sources.values) {
    for (final m in _classHeader.allMatches(lines.join('\n'))) {
      final rest = m.group(2)!;
      parents[m.group(1)!] =
          RegExp(r'\bextends\s+(\w+)').firstMatch(rest)?.group(1);
      if (RegExp(r'\bEquatableMixin\b').hasMatch(rest)) {
        mixesIn.add(m.group(1)!);
      }
    }
  }
  // A state, not an event or a model: the class that brings in Equatable is
  // named ...State.
  bool isEquatable(String name, [int depth = 0]) {
    if (mixesIn.contains(name)) return name.endsWith('State');
    final parent = parents[name];
    if (parent == null || depth > 20) return false;
    return parent == 'Equatable'
        ? name.endsWith('State')
        : isEquatable(parent, depth + 1);
  }

  return {
    for (final name in parents.keys)
      if (isEquatable(name)) name
  };
}

/// Every Equatable state class under lib/, keyed `path ClassName`, with the fields
/// its props leave out. A class with fields of its own and no props of its
/// own counts too: whatever props it inherits can't name them.
Map<String, _ClassInfo> _classes(Map<String, List<String>> sources) {
  final equatable = _equatableClasses(sources);
  final result = <String, _ClassInfo>{};
  sources.forEach((path, lines) {
    final text = lines.join('\n');
    for (final header in _classHeader.allMatches(text)) {
      if (!equatable.contains(header.group(1))) continue;
      final body = _body(text, header.end);
      final top = _topLevel(body);
      final fields = {
        for (final m
            in RegExp(r'(?:^|(?<=[;}]))\s*(?:@\w+\s+)*(?:late\s+)?final\s+'
                    r'[^;=]*?\s(\w+)\s*[;=]')
                .allMatches(top))
          m.group(1)!,
      };
      if (fields.isEmpty) continue;
      final props =
          RegExp(r'get\s+props\s*(?:=>\s*|\{[^]*?return\s*)\[([^]*?)\]\s*;')
              .firstMatch(body);
      final named = props == null
          ? const <String>{}
          : RegExp(r'\b\w+\b')
              .allMatches(props.group(1)!)
              .map((m) => m[0]!)
              .toSet();
      final missing = fields.difference(named);
      if (missing.isNotEmpty) {
        result['$path ${header.group(1)}'] = _ClassInfo(missing);
      }
    }
  });
  return result;
}

/// The text from [start] up to the brace that closes the class.
String _body(String text, int start) {
  var depth = 1;
  var i = start;
  while (i < text.length && depth > 0) {
    final c = text[i];
    if (c == '{') depth++;
    if (c == '}') depth--;
    i++;
  }
  return text.substring(start, i - 1);
}

/// [body] without what's inside its braces and brackets: the class's own
/// declarations, not its methods' or constructors' contents.
String _topLevel(String body) {
  final out = StringBuffer();
  var depth = 0;
  for (final c in body.split('')) {
    if (c == '{' || c == '(' || c == '[') {
      depth++;
      continue;
    }
    if (c == '}' || c == ')' || c == ']') {
      depth--;
      if (depth == 0 && c == '}') out.write(';');
      continue;
    }
    if (depth == 0) out.write(c);
  }
  return out.toString();
}
