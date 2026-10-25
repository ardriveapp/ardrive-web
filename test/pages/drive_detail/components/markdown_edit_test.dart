import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

/// Editing a markdown file opens a loader, fetches the file, then the editor.
/// A failure before the loader opened - reading the drive, say - used to pop
/// a route anyway, closing whatever the reader was looking at.
void main() {
  testWidgets('a failure before the loader opens closes nothing but itself',
      (tester) async {
    final driveDao = MockDriveDao();
    when(() => driveDao.driveById(driveId: any(named: 'driveId')))
        .thenThrow(Exception('no such drive'));

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<DriveDao>.value(value: driveDao),
            RepositoryProvider<ConfigService>.value(value: MockConfigService()),
            RepositoryProvider<ArweaveService>.value(
                value: MockArweaveService()),
            RepositoryProvider<ArDriveCrypto>.value(value: MockArDriveCrypto()),
          ],
          child: BlocProvider<ProfileCubit>.value(
            value: MockProfileCubit(),
            child: MaterialApp(
              home: const Text('Explorer'),
              routes: {
                '/preview': (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => handleMarkdownFileEdit(
                          context,
                          createMockFileDataTableItem(name: 'notes.md'),
                        ),
                        child: const Text('Edit'),
                      ),
                    ),
              },
            ),
          ),
        ),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/preview');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget,
        reason: 'the error is shown');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget,
        reason: 'the page the edit started from is still open');
  });
}
