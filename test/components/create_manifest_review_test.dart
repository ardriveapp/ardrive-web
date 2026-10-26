import 'dart:typed_data';

import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/components/create_manifest_form.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockCreateManifestCubit extends MockCubit<CreateManifestState>
    implements CreateManifestCubit {}

void main() {
  // With the name step open, the review was taller than a laptop window and
  // did not scroll, so Create deployment sat below the window, out of reach.
  testWidgets('Create deployment stays in view on a short window',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final file = await IOFile.fromData(
      Uint8List(425),
      name: 'e2e-names-site',
      lastModifiedDate: DateTime(2026),
    );
    final cubit = _MockCreateManifestCubit();
    whenListen(
      cubit,
      const Stream<CreateManifestState>.empty(),
      initialState: CreateManifestUploadReview(
        manifestSize: 425,
        manifestName: 'e2e-names-site',
        folderHasPendingFiles: true,
        manifestFile: file,
        freeStatus: FreeUploadStatus.free,
        canUpload: true,
        drive: Drive(
          id: 'drive-1',
          rootFolderId: 'root',
          ownerAddress: 'owner',
          name: 'A public drive',
          privacy: 'public',
          lastBlockHeight: 0,
          isHidden: false,
          dateCreated: DateTime(2024),
          lastUpdated: DateTime(2024),
        ),
        parentFolder: FolderEntry(
          id: 'root',
          driveId: 'drive-1',
          name: 'root',
          path: '',
          dateCreated: DateTime(2024),
          lastUpdated: DateTime(2024),
          isGhost: false,
          isHidden: false,
        ),
      ),
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: BlocProvider<CreateManifestCubit>.value(
                value: cubit,
                child: const CreateManifestForm(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final create = find.text('Create deployment');
    expect(create, findsOneWidget);
    expect(tester.getBottomRight(create).dy, lessThanOrEqualTo(520));
  });
}
