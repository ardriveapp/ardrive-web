import 'package:ardrive/download/download_utils.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockMultipleDownloadBloc
    extends MockBloc<MultipleDownloadEvent, MultipleDownloadState>
    implements MultipleDownloadBloc {}

MultiDownloadFile _file(String name) => MultiDownloadFile(
      driveId: 'drive',
      fileId: name,
      fileName: name,
      txId: 'tx-$name',
      size: 1,
    );

void main() {
  // A drive of three files in two folders plus the root, in the order a
  // whole-drive download lists it: each folder's entry, then what it holds.
  final items = <MultiDownloadItem>[
    MultiDownloadFolder('Drive/'),
    MultiDownloadFolder('Drive/a/'),
    _file('Drive/a/1.txt'),
    MultiDownloadFolder('Drive/b/'),
    _file('Drive/b/2.txt'),
    _file('Drive/3.txt'),
  ];

  Future<void> pumpAt(WidgetTester tester, int currentFileIndex) async {
    final bloc = _MockMultipleDownloadBloc();
    whenListen(
      bloc,
      const Stream<MultipleDownloadState>.empty(),
      initialState: MultipleDownloadInProgress(
        files: items,
        currentFileIndex: currentFileIndex,
      ),
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BlocProvider<MultipleDownloadBloc>.value(
              value: bloc,
              child: const MultipleFilesDownload(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the multi-file download progress title', () {
    // The confirmation asks "Download 3 files?", so the progress counts the
    // same three. It used to count the folder entries too: "of 6".
    testWidgets('counts files, not folders', (tester) async {
      await pumpAt(tester, 0);
      expect(find.text('Downloading file 1 of 3'), findsOneWidget);
    });

    testWidgets('names the next file while it adds a folder', (tester) async {
      // Index 3 is folder b, after one file.
      await pumpAt(tester, 3);
      expect(find.text('Downloading file 2 of 3'), findsOneWidget);
    });

    testWidgets('ends on the last file', (tester) async {
      await pumpAt(tester, items.length - 1);
      expect(find.text('Downloading file 3 of 3'), findsOneWidget);
    });
  });
}
