import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Search on the one page that did not have it.
///
/// `DriveDao.search` takes no drive id - it is global across every drive, plus
/// ARNS names - so All Drives had no reason to be the single screen without a
/// way in. Desktop search lived in `AppTopBar`, which only the explorer mounts,
/// and the drives list builds its own chrome; mobile search was opt-in on
/// `MobileAppBar` and this page did not opt in.
///
/// Read as source rather than pumped, for the same reason the item-menu parity
/// test is: the failure mode is a surface *missing* the control, and the two
/// surfaces are different widget trees behind a `ScreenTypeLayout`. A widget
/// test proves whichever branch it rendered, which is exactly the half that was
/// never the problem.
///
/// The chrome is shared by every list page now (Your drives, Web pages, Names
/// and one name's page), so it is read where it lives, and each page is
/// checked to wear it.
void main() {
  final page = File(
    'lib/components/list_page/list_page_layout.dart',
  ).readAsStringSync();

  test('the desktop chrome carries a search field', () {
    expect(page.contains('ListPageSearchField()'), isTrue);
  });

  test('every list page wears that chrome', () {
    for (final path in [
      'lib/drives_list/presentation/drives_list_page.dart',
      'lib/web_pages/presentation/web_pages_page.dart',
      'lib/arns/presentation/names_page/names_page.dart',
    ]) {
      expect(
        File(path).readAsStringSync().contains('ListPageChrome('),
        isTrue,
        reason: '$path builds its own chrome',
      );
    }
  });

  test('the mobile bar opts into search', () {
    expect(page.contains('showSearch: true'), isTrue);
  });

  /// Both surfaces have to route results through the router, not the modal's
  /// own cubit. Selecting a drive here replaces the subtree, so that cubit is
  /// torn down mid-navigation and the reader lands at the drive root instead of
  /// the file they searched for.
  test('both routes a result through requestFolder', () {
    expect(
      'requestFolder('.allMatches(page).length,
      2,
      reason: 'one for the desktop field, one for the mobile bar; a surface '
          'without it navigates to the wrong place',
    );
  });

  test('and the explorer keeps its own path', () {
    final shell = File('lib/app_shell.dart').readAsStringSync();

    // `MobileAppBar` is worn by the explorer, the drives list and the no-drives
    // page. The callback is optional so the explorer keeps calling `openFolder`
    // on its own long-lived cubit, which is correct there.
    expect(
      shell.contains('this.onSearchNavigateToFolder,'),
      isTrue,
      reason: 'forcing every screen to supply one would make the explorer take '
          'a slower road to the same place',
    );
  });
}
