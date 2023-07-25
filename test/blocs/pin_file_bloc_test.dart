// Unit tests for the PinFileBloc class.

import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFileIdResolver extends Mock implements FileIdResolver {}

void main() {
  group('PinFileBloc', () {
    final FileIdResolver fileIdResolver = MockFileIdResolver();

    const String validName = 'Ñoquis con tuco 🍝😋';
    const String validTxId_1 = 'HelloHelloHelloHelloHelloHelloHelloH-+_ABCD';
    const String validTxId_2 = '+_-1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcd';
    const String validFileId_1 = '01234567-89ab-cdef-0123-456789abcdef';
    const String validFileId_2 = '00000000-0000-0000-0000-000000000000';

    const String invalidName = ' Buseca.mp3 🍛🤢 ';
    const String invalidId = 'not a tx id neither a file id';

    final DateTime mockDate = DateTime(1234567);

    setUp(() {
      when(() => fileIdResolver.requestForTransactionId(validTxId_1))
          .thenAnswer(
        (_) async => FileInfo(
          isPrivate: false,
          maybeName: null,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
        ),
      );
      when(() => fileIdResolver.requestForTransactionId(validTxId_2))
          .thenAnswer(
        (_) async => FileInfo(
          isPrivate: false,
          maybeName: null,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_2,
        ),
      );
      when(() => fileIdResolver.requestForFileId(validFileId_1)).thenAnswer(
        (_) async => FileInfo(
          isPrivate: false,
          maybeName: validName,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
        ),
      );
      when(() => fileIdResolver.requestForFileId(validFileId_2)).thenAnswer(
        (_) async => FileInfo(
          isPrivate: false,
          maybeName: validName,
          dataContentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_2,
        ),
      );
    });

    blocTest<PinFileBloc, PinFileState>(
      'initial state',
      build: () => PinFileBloc(fileIdResolver: fileIdResolver),
      act: (bloc) => bloc
        ..add(
          const FieldsChanged(name: '', id: ''),
        ),
      expect: () => [const PinFileInitial()],
    );

    group('fields synchronous validation', () {
      blocTest<PinFileBloc, PinFileState>(
        'valid fields',
        build: () => PinFileBloc(fileIdResolver: fileIdResolver),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: validName, id: validTxId_1),
          )
          ..add(
            const FieldsChanged(name: validName, id: validTxId_2),
          )
          ..add(
            const FieldsChanged(name: validName, id: validFileId_1),
          )
          ..add(
            const FieldsChanged(name: validName, id: validFileId_2),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validTxId_1,
            name: validName,
          ),
          PinFileFieldsValid(
            id: validTxId_1,
            name: validName,
            isPrivate: false,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
          ),
          const PinFileNetworkCheckRunning(
            id: validTxId_2,
            name: validName,
          ),
          PinFileFieldsValid(
            id: validTxId_2,
            name: validName,
            isPrivate: false,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_2,
          ),
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: validName,
          ),
          PinFileFieldsValid(
            id: validFileId_1,
            name: validName,
            isPrivate: false,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
          ),
          const PinFileNetworkCheckRunning(
            id: validFileId_2,
            name: validName,
          ),
          PinFileFieldsValid(
            id: validFileId_2,
            name: validName,
            isPrivate: false,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_2,
          ),
        ],
      );

      blocTest<PinFileBloc, PinFileState>(
        'invalid synchronous validation',
        build: () => PinFileBloc(fileIdResolver: fileIdResolver),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: invalidName, id: validTxId_1),
          )
          ..add(
            const FieldsChanged(name: invalidName, id: validFileId_1),
          )
          ..add(
            const FieldsChanged(name: validName, id: invalidId),
          )
          ..add(
            const FieldsChanged(name: invalidName, id: invalidId),
          )
          ..add(
            const FieldsChanged(name: '', id: invalidId),
          )
          ..add(
            const FieldsChanged(name: invalidName, id: ''),
          ),
        expect: () => [
          const PinFileFieldsValidationError(
            id: validTxId_1,
            name: invalidName,
            nameValidation: NameValidationResult.invalid,
            idValidation: IdValidationResult.validTransactionId,
          ),
          const PinFileFieldsValidationError(
            id: validFileId_1,
            name: invalidName,
            nameValidation: NameValidationResult.invalid,
            idValidation: IdValidationResult.validFileId,
          ),
          const PinFileFieldsValidationError(
            id: invalidId,
            name: validName,
            nameValidation: NameValidationResult.valid,
            idValidation: IdValidationResult.invalid,
          ),
          const PinFileFieldsValidationError(
            id: invalidId,
            name: invalidName,
            nameValidation: NameValidationResult.invalid,
            idValidation: IdValidationResult.invalid,
          ),
          const PinFileFieldsValidationError(
            id: invalidId,
            name: '',
            nameValidation: NameValidationResult.required,
            idValidation: IdValidationResult.invalid,
          ),
          const PinFileFieldsValidationError(
            id: '',
            name: invalidName,
            nameValidation: NameValidationResult.invalid,
            idValidation: IdValidationResult.required,
          ),
        ],
      );

      blocTest<PinFileBloc, PinFileState>(
        'network check won\'t run when id doesn\'t change while fields are '
        'valid',
        build: () => PinFileBloc(fileIdResolver: fileIdResolver),
        seed: () => PinFileFieldsValid(
          id: validFileId_1,
          name: validName,
          isPrivate: false,
          contentType: 'application/json',
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: 'otro nombre', id: validFileId_1),
          )
          ..add(
            const FieldsChanged(name: 'pew! pew! pew!', id: validFileId_1),
          ),
        expect: () => [
          PinFileFieldsValid(
            id: validFileId_1,
            name: 'otro nombre',
            isPrivate: false,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
          ),
          PinFileFieldsValid(
            id: validFileId_1,
            name: 'pew! pew! pew!',
            isPrivate: false,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_1,
          ),
        ],
      );

      blocTest<PinFileBloc, PinFileState>(
        'network check won\'t run when id doesn\'t change while network check '
        'is running',
        build: () => PinFileBloc(fileIdResolver: fileIdResolver),
        seed: () => const PinFileNetworkCheckRunning(
          id: validFileId_1,
          name: validName,
        ),
        act: (bloc) => bloc
          ..add(
            const FieldsChanged(name: 'otro nombre', id: validFileId_1),
          )
          ..add(
            const FieldsChanged(name: 'pew! pew! pew!', id: validFileId_1),
          ),
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: 'otro nombre',
          ),
          const PinFileNetworkCheckRunning(
            id: validFileId_1,
            name: 'pew! pew! pew!',
          ),
        ],
      );
    });
  });
}
