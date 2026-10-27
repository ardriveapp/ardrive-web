import 'dart:async';

import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

void main() {
  late MockDrivesCubit drives;
  late StreamController<String> selections;

  setUp(() {
    drives = MockDrivesCubit();
    selections = StreamController<String>.broadcast();
    when(() => drives.driveSelections).thenAnswer((_) => selections.stream);
  });

  tearDown(() => selections.close());

  // The router builds its shells above the providers that hold the drives
  // cubit. The Names shell read the cubit where it was built, so opening
  // On the web › Names threw "Provider<DrivesCubit> not found" and left a
  // blank page.
  testWidgets('built where there is no drives cubit, it reads the one below',
      (tester) async {
    final opened = <String>[];
    final shell = ArNSNamesShell(
      onOpenDrive: opened.add,
      child: const SizedBox(),
    );

    await tester.pumpWidget(
      BlocProvider<DrivesCubit>.value(value: drives, child: shell),
    );
    expect(tester.takeException(), isNull);

    selections.add('drive-1');
    await tester.pump();

    expect(opened, ['drive-1']);
  });
}
