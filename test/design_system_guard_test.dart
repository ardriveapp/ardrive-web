import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the app on the design system where the compiler can't.
///
/// The old components are gone, so using one no longer compiles. What still
/// compiles is drawing around the system: a Material spinner instead of
/// ArDriveSpinner, a Material colour or a literal colour instead of a token,
/// a Material menu or dropdown instead of the app's menus. This scans the
/// app's and ardrive_ui's sources for those.
///
/// A file that has a reason to break a rule goes in [_spinnerExceptions],
/// [_colourExceptions] or [_menuExceptions] with that reason. An exception that no longer matches
/// anything fails too, so the lists stay honest.
void main() {
  final sources = _sources();

  test(
      'spinners and progress bars are ArDriveSpinner and '
      'ArDriveLinearProgress', () {
    expect(
      _violations(sources, _rawProgress, _spinnerExceptions),
      isEmpty,
      reason: 'Use ArDriveSpinner or ArDriveLinearProgress, or add the file '
          'to _spinnerExceptions with a reason.',
    );
  });

  test('colours come from colorTokens, not Material colours or literals', () {
    expect(
      _violations(sources, _rawColour, _colourExceptions),
      isEmpty,
      reason: 'Use a colorTokens value, or add the file to '
          '_colourExceptions with a reason.',
    );
  });

  test('menus and dropdowns are the app\'s own', () {
    expect(
      _violations(sources, _rawMenu, _menuExceptions),
      isEmpty,
      reason: 'Use ArDriveSelectField, ArDriveChoiceMenu, ArDriveDropdown, '
          'ArDriveSubmenu or ArDriveMenuAnchor, or add the file to '
          '_menuExceptions with a reason.',
    );
  });

  test('IDs and addresses are shortened by shortenId alone', () {
    expect(
      _violations(sources, _rawShortening, _shorteningExceptions),
      isEmpty,
      reason: 'Use shortenId (lib/utils/truncate_string.dart), so one ID or '
          'address reads the same everywhere, or add the file to '
          '_shorteningExceptions with a reason.',
    );
  });

  test('every exception still needs to be one', () {
    final stale = <String>[
      for (final path in _spinnerExceptions.keys)
        if (!_matches(sources[path], _rawProgress)) path,
      for (final path in _colourExceptions.keys)
        if (!_matches(sources[path], _rawColour)) path,
      for (final path in _menuExceptions.keys)
        if (!_matches(sources[path], _rawMenu)) path,
      for (final path in _shorteningExceptions.keys)
        if (!_matches(sources[path], _rawShortening)) path,
    ];
    expect(stale, isEmpty, reason: 'Remove these from the exception lists.');
  });
}

/// A Material spinner or bar, drawn directly.
final _rawProgress =
    RegExp(r'\b(CircularProgressIndicator|LinearProgressIndicator)\b');

/// A Material colour other than transparent, or a literal colour.
final _rawColour = RegExp(r'\bColors\.(?!transparent\b)\w+|\bColor\(0x');

/// A Material or reactive_forms menu or dropdown. Their items sit under the
/// page in the browser's accessibility tree, and they look like no other
/// menu in the app.
final _rawMenu = RegExp(
  r'\b(MenuAnchor|MenuController|MenuItemButton|SubmenuButton|PopupMenuButton|'
  r'DropdownButton|DropdownButtonFormField|DropdownMenu|'
  r'ReactiveDropdownField)\b'
  // Material's showMenu() call, not the showMenu string for a menu button.
  r'|(?<![.\w])showMenu\s*[<(]',
);

/// A string cut to its ends by hand: `x.substring(0, 6)}...`, with a number
/// or a variable for the length, or `truncateString(`, the shape of a
/// shortened ID or address.
final _rawShortening =
    RegExp(r'substring\(0, ?\w+\)\}\.\.\.|\btruncateString\(');

/// Where colours are defined: the tokens and the palettes they're built on.
const _styleDir = 'packages/ardrive_ui/lib/src/styles/';

const _spinnerExceptions = {
  'packages/ardrive_ui/lib/src/components/spinner.dart':
      'ArDriveSpinner and ArDriveLinearProgress themselves',
  'lib/components/app_top_bar.dart':
      'the sync ring around the refresh glyph: an indicator, not a spinner',
  'lib/components/upload_form.dart':
      'the upload\'s percentage ring: an indicator, not a spinner',
};

const _colourExceptions = {
  'lib/turbo/topup/views/unified/wallet_connection_view.dart':
      'wallet and token brand colours',
  'lib/turbo/topup/views/unified/inline_crypto_payment.dart':
      'wallet and token brand colours',
  'lib/turbo/topup/views/unified/crypto_confirmation_view.dart':
      'token brand colours',
  'lib/turbo/topup/components/payment_method_selector.dart':
      'a token\'s mark: white on its brand colour',
  'lib/components/profile_card.dart': 'Ethereum and Solana brand colours',
  'lib/pages/drive_detail/components/fs_entry_preview_widget.dart':
      'the black stage behind media, in both themes',
  'lib/permanence/permanence_panel.dart':
      'PermanenceShareCard, rendered as an image to share',
  'lib/publication/domain/publication_social_card.dart':
      'rendered as an image to share',
  'lib/authentication/login/views/tiles/tiles_view.dart':
      'the sign-in bento\'s illustration: its peach, deep red and photo scrim',
};

const _menuExceptions = <String, String>{};

const _shorteningExceptions = {
  'lib/utils/truncate_string.dart': 'shortenId and the helper under it',
  'lib/web_pages/domain/web_page.dart': 'a URL path, not an ID',
  'lib/sync/domain/repositories/sync_repository.dart':
      'an error message cut short for the log',
  'lib/services/solana/implementations/solana_provider_web.dart': 'a log line',
  'lib/components/truncated_address_new.dart':
      'dead, nothing builds it; goes with the audit\'s dead code',
};

/// Each Dart source under lib/ and ardrive_ui's lib/, with comments taken
/// out, keyed by its path from the app root. Generated code is left out.
Map<String, List<String>> _sources() {
  final files = <String, List<String>>{};
  for (final root in ['lib', 'packages/ardrive_ui/lib']) {
    for (final entity in Directory(root).listSync(recursive: true)) {
      final path = entity.path.replaceAll(r'\', '/');
      if (entity is! File ||
          !path.endsWith('.dart') ||
          path.endsWith('.g.dart') ||
          path.startsWith('lib/services/arweave/graphql/')) {
        continue;
      }
      files[path] = entity
          .readAsLinesSync()
          .map((line) => line.replaceFirst(RegExp(r'//.*$'), ''))
          .toList();
    }
  }
  return files;
}

bool _matches(List<String>? lines, RegExp rule) =>
    lines != null && lines.any(rule.hasMatch);

List<String> _violations(
  Map<String, List<String>> sources,
  RegExp rule,
  Map<String, String> exceptions,
) {
  final found = <String>[];
  sources.forEach((path, lines) {
    if (path.startsWith(_styleDir) || exceptions.containsKey(path)) return;
    for (var i = 0; i < lines.length; i++) {
      if (rule.hasMatch(lines[i])) found.add('$path:${i + 1}');
    }
  });
  return found;
}
