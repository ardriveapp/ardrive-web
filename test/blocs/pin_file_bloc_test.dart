// Unit tests for the PinFileBloc class.

import 'package:ardrive/blocs/pin_file/file_to_pin_ressolver.dart';
import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFileIdRessolver extends Mock implements FileIdRessolver {}

void main() {
  group('PinFileBloc', () {
    final FileIdRessolver fileIdRessolver = MockFileIdRessolver();

    setUp(() {
      when(() => fileIdRessolver.resolve(any())).thenAnswer(
        (_) async => FileData(
          isPrivate: false,
          maybeName: 'name',
          contentType: 'text/plain',
          maybeLastUpdated: DateTime.now(),
          maybeLastModified: DateTime.now(),
          dateCreated: DateTime.now(),
          size: 0,
          dataTxId: 'dataTxId',
        ),
      );
    });

    blocTest<PinFileBloc, PinFileState>(
      'initial state  ',
      build: () => PinFileBloc(fileIdRessolver: fileIdRessolver)
        ..add(
          const FiledsChanged(name: '', id: ''),
        ),
      expect: () => [const PinFileInitial()],
    );
  });
}
