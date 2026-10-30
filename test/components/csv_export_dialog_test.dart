import 'dart:typed_data';

import 'package:ardrive/blocs/data_export/data_export_cubit.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDataExportCubit extends MockCubit<DataExportState>
    implements DataExportCubit {}

/// The CSV export dialog checked the download dialog's states, which the
/// export cubit never emits, so it drew nothing: an invisible dialog that
/// could not be dismissed, and a failure nobody saw.
void main() {
  late _MockDataExportCubit cubit;

  setUp(() => cubit = _MockDataExportCubit());

  Future<void> open(WidgetTester tester, DataExportState state) async {
    when(() => cubit.state).thenReturn(state);
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => BlocProvider<DataExportCubit>.value(
                  value: cubit,
                  child: const CsvExportDialog(),
                ),
              ),
              child: const Text('Export'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('says it is exporting while it works', (tester) async {
    await open(tester, const DataExportInProgress());

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(find.text('Downloading CSV...'), findsOneWidget);
    expect(find.byType(ArDriveSpinner), findsOneWidget);
    final cancel =
        tester.widget<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(cancel.text, 'Cancel');
    expect(cancel.variant, ButtonVariant.secondary);
  });

  testWidgets('Cancel stops the export and closes', (tester) async {
    when(() => cubit.abort()).thenReturn(null);
    await open(tester, const DataExportInProgress());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verify(() => cubit.abort()).called(1);
    expect(find.byType(CsvExportDialog), findsNothing);
  });

  testWidgets('offers no Cancel while the file is being saved', (tester) async {
    await open(
      tester,
      DataExportSuccess(
        bytes: Uint8List(0),
        fileName: 'export.csv',
        mimeType: 'text/csv',
        lastModified: DateTime(2026),
      ),
    );

    expect(find.byType(ArDriveSpinner), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a failure is shown, with a way out', (tester) async {
    await open(tester, DataExportFailure());

    expect(find.text('File download failed'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(CsvExportDialog), findsNothing);
  });
}
