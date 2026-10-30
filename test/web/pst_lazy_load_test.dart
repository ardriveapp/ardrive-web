// ignore_for_file: avoid_web_libraries_in_flutter
@TestOn('browser')
library;

import 'dart:html' as html;

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pst/pst.dart';

/// The Warp fallback for the community contract asks the lazy loader for
/// pst.min.js before it reads `window.pst`.
///
/// index.html stopped loading pst.min.js in 2.82.0 and nothing called
/// `LazyLoader.loadPst()`, so `window.pst` was undefined and the fallback
/// always failed. The real pst.min.js reads from Warp's network, so a stand-in
/// loader plays its part here: it defines `window.pst` only when asked.
void main() {
  setUpAll(() {
    html.document.head!.append(html.ScriptElement()
      ..text = '''
        window.pstLoads = 0;
        window.LazyLoader = {
          loadPst: function() {
            window.pstLoads++;
            window.pst = {
              readContractAsStringPromise: function(id) {
                return Promise.resolve(
                  JSON.stringify({state: {contract: id, settings: []}}));
              },
            };
            return Promise.resolve();
          },
        };
      ''');
  });

  test('loads pst.min.js before it reads the contract', () async {
    final state = await WarpContractReader().readContract(
      TransactionID('-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ'),
    );

    expect(state['contract'], '-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ');
  });
}
