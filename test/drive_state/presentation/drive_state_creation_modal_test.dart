import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_cubit/drive_state_creation_cubit.dart';
import 'package:ardrive/drive_state/presentation/drive_state_creation_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// The confirmation surface. Two things are worth a widget test here: that the
/// user is told what would be published before they can agree to it, and that
/// a refusal offers no way past itself.
void main() {
  late _MockCubit cubit;

  setUp(() => cubit = _MockCubit());

  Widget wrap(DriveStateCreationState state) {
    when(() => cubit.state).thenReturn(state);
    whenListen(cubit, const Stream<DriveStateCreationState>.empty());

    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        home: Scaffold(
          body: BlocProvider<DriveStateCreationCubit>.value(
            value: cubit,
            child: const DriveStateCreationModal(driveName: 'My Drive'),
          ),
        ),
      ),
    );
  }

  PreparedDriveStateArtifact artifact() => PreparedDriveStateArtifact(
        entity: DriveStateEntity(
          id: 'artifact-id',
          driveId: 'drive-id',
          blockEnd: 1814228,
          dataStart: 0,
          dataEnd: 1814228,
          entityCount: 12,
          cipher: 'AES256-GCM',
          cipherIv: 'aXY=',
        ),
        driveId: 'drive-id',
        driveName: 'My Drive',
        entityCount: 12,
        sizeInBytes: 6979321,
      );

  testWidgets('the confirmation shows what would be published',
      (tester) async {
    await tester.pumpWidget(wrap(DriveStateCreationReady(artifact())));
    await tester.pumpAndSettle();

    expect(find.text('My Drive'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('6.66 MiB'), findsOneWidget);
    expect(find.text('0 to 1814228'), findsOneWidget);
    expect(find.textContaining('permanent'), findsOneWidget);
    expect(find.textContaining('Nothing has been uploaded yet'),
        findsOneWidget);
  });

  testWidgets('nothing is published until the user asks for it',
      (tester) async {
    await tester.pumpWidget(wrap(DriveStateCreationReady(artifact())));
    await tester.pumpAndSettle();

    when(() => cubit.publish()).thenAnswer((_) async {});

    verifyNever(() => cubit.publish());

    // The button's own callback, invoked directly: this asserts what the
    // confirm action is wired to, without depending on where in a modal's
    // layout the button lands under a test-sized viewport.
    final publish = tester.widget<ArDriveButtonNew>(
      find.widgetWithText(ArDriveButtonNew, 'Publish'),
    );

    publish.onPressed!();
    await tester.pump();

    verify(() => cubit.publish()).called(1);
  });

  testWidgets('a refusal explains itself and offers no way past it',
      (tester) async {
    await tester.pumpWidget(wrap(DriveStateCreationRefused(
      refusal: DriveStateCreationRefusal.syncSkippedEntities,
      reason: 'The last sync of this drive could not read 3 items.',
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not read 3 items'), findsOneWidget);
    expect(find.textContaining('would record the gap forever'), findsOneWidget);
    expect(find.text('Publish'), findsNothing);
    verifyNever(() => cubit.publish());
  });
}

class _MockCubit extends MockCubit<DriveStateCreationState>
    implements DriveStateCreationCubit {}
