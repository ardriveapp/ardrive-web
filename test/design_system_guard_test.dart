import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the app on the design system where the compiler can't.
///
/// The old components are gone, so using one no longer compiles. What still
/// compiles is drawing around the system: a Material spinner instead of
/// ArDriveSpinner, a Material colour or a literal colour instead of a token.
/// This scans the app's and ardrive_ui's sources for those.
///
/// A file that has a reason to break a rule goes in [_spinnerExceptions] or
/// [_colourExceptions] with that reason. An exception that no longer matches
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

  test('every exception still needs to be one', () {
    final stale = <String>[
      for (final path in _spinnerExceptions.keys)
        if (!_matches(sources[path], _rawProgress)) path,
      for (final path in _colourExceptions.keys)
        if (!_matches(sources[path], _rawColour)) path,
    ];
    expect(stale, isEmpty, reason: 'Remove these from the exception lists.');
  });
}

/// A Material spinner or bar, drawn directly.
final _rawProgress =
    RegExp(r'\b(CircularProgressIndicator|LinearProgressIndicator)\b');

/// A Material colour other than transparent, or a literal colour.
final _rawColour = RegExp(r'\bColors\.(?!transparent\b)\w+|\bColor\(0x');

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
  'lib/turbo/topup/views/crypto_topup/components/wallet_selector_modal.dart':
      'wallet brand colours',
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
  'lib/authentication/login/views/tutorials_view.dart':
      'the sign-in illustration\'s texture',
  'lib/authentication/components/dot_pattern_painter.dart':
      'the sign-in illustration\'s texture',
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
