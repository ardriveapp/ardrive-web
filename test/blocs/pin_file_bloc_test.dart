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

    const String validName = 'Ñoquis con tuco 🍝😋';
    const String validTxId_1 = 'HelloHelloHelloHelloHelloHelloHelloH-+_ABCD';
    const String validTxId_2 = '+_-1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcd';
    const String validFileId_1 = '01234567-89ab-cdef-0123-456789abcdef';
    const String validFileId_2 = '00000000-0000-0000-0000-000000000000';

    const String invalidName = ' Buseca.mp3 🍛🤢 ';
    const String invalidId = 'not a tx id neither a file id';

    final DateTime mockDate = DateTime(1234567);

    setUp(() {
      when(() => fileIdRessolver.resolve(validTxId_1)).thenAnswer(
        (_) async => FileData(
          isPrivate: false,
          maybeName: null,
          contentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
        ),
      );
      when(() => fileIdRessolver.resolve(validTxId_2)).thenAnswer(
        (_) async => FileData(
          isPrivate: false,
          maybeName: null,
          contentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_2,
        ),
      );
      when(() => fileIdRessolver.resolve(validFileId_1)).thenAnswer(
        (_) async => FileData(
          isPrivate: false,
          maybeName: validName,
          contentType: 'application/json',
          maybeLastUpdated: mockDate,
          maybeLastModified: mockDate,
          dateCreated: mockDate,
          size: 1,
          dataTxId: validTxId_1,
        ),
      );
      when(() => fileIdRessolver.resolve(validFileId_2)).thenAnswer(
        (_) async => FileData(
          isPrivate: false,
          maybeName: validName,
          contentType: 'application/json',
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
      build: () => PinFileBloc(fileIdRessolver: fileIdRessolver)
        ..add(
          const FiledsChanged(name: '', id: ''),
        ),
      expect: () => [const PinFileInitial()],
    );

    group('fields synchronous validation', () {
      blocTest(
        'valid fields',
        build: () {
          return PinFileBloc(fileIdRessolver: fileIdRessolver)
            ..add(
              const FiledsChanged(name: validName, id: validTxId_1),
            )
            ..add(
              const FiledsChanged(name: validName, id: validTxId_2),
            )
            ..add(
              const FiledsChanged(name: validName, id: validFileId_1),
            )
            ..add(
              const FiledsChanged(name: validName, id: validFileId_2),
            );
        },
        expect: () => [
          const PinFileNetworkCheckRunning(
            id: validTxId_1,
            name: validName,
          ),
          PinFileFieldsValid(
            id: validTxId_1,
            name: validName,
            isPrivate: false,
            maybeName: null,
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
            maybeName: null,
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
            maybeName: validName,
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
            maybeName: validName,
            contentType: 'application/json',
            maybeLastUpdated: mockDate,
            maybeLastModified: mockDate,
            dateCreated: mockDate,
            size: 1,
            dataTxId: validTxId_2,
          ),
        ],
      );

      blocTest('invalid synchronous validation', build: () {
        return PinFileBloc(fileIdRessolver: fileIdRessolver)
          ..add(
            const FiledsChanged(name: invalidName, id: validTxId_1),
          )
          ..add(
            const FiledsChanged(name: invalidName, id: validFileId_1),
          )
          ..add(
            const FiledsChanged(name: validName, id: invalidId),
          )
          ..add(
            const FiledsChanged(name: invalidName, id: invalidId),
          )
          ..add(
            const FiledsChanged(name: '', id: invalidId),
          )
          ..add(
            const FiledsChanged(name: invalidName, id: ''),
          );
      }, expect: () {
        return [
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
        ];
      });
    });
  });
}
