import 'dart:convert';

import 'package:ardrive/blocs/note_create/note_create_cubit.dart';
import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteCreateCubit', () {
    late NoteCreateCubit cubit;

    setUp(() {
      cubit = NoteCreateCubit(
        driveId: 'test-drive-id',
        parentFolderId: 'test-folder-id',
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state is NoteCreateEditing with empty values', () {
      expect(
        cubit.state,
        const NoteCreateEditing(
          noteName: '',
          content: '',
          isValidName: false,
          viewMode: NoteViewMode.splitView,
        ),
      );
    });

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateNoteName updates name and validates',
      build: () => cubit,
      act: (cubit) => cubit.updateNoteName('My Note'),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.noteName, 'noteName', 'My Note')
            .having((s) => s.isValidName, 'isValidName', true)
            .having((s) => s.nameError, 'nameError', null),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateNoteName invalidates empty name',
      build: () => cubit,
      act: (cubit) => cubit.updateNoteName(''),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.noteName, 'noteName', '')
            .having((s) => s.isValidName, 'isValidName', false)
            .having((s) => s.nameError, 'nameError', isNotNull),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateNoteName invalidates names with forward slash',
      build: () => cubit,
      act: (cubit) => cubit.updateNoteName('Invalid/Name'),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.isValidName, 'isValidName', false)
            .having((s) => s.nameError, 'nameError', isNotNull),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateNoteName invalidates names with backslash',
      build: () => cubit,
      act: (cubit) => cubit.updateNoteName('Invalid\\Name'),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.isValidName, 'isValidName', false)
            .having((s) => s.nameError, 'nameError', isNotNull),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateNoteName invalidates names with asterisk',
      build: () => cubit,
      act: (cubit) => cubit.updateNoteName('Invalid*Name'),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.isValidName, 'isValidName', false)
            .having((s) => s.nameError, 'nameError', isNotNull),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateNoteName allows names with .md extension',
      build: () => cubit,
      act: (cubit) => cubit.updateNoteName('MyNote.md'),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.noteName, 'noteName', 'MyNote.md')
            .having((s) => s.isValidName, 'isValidName', true),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'updateContent updates markdown content',
      build: () => cubit,
      act: (cubit) => cubit.updateContent('# Hello\n\nWorld'),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.content, 'content', '# Hello\n\nWorld'),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'setViewMode changes view mode',
      build: () => cubit,
      act: (cubit) => cubit.setViewMode(NoteViewMode.editOnly),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.editOnly),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'cycleViewMode cycles from splitView to previewOnly',
      build: () => cubit,
      act: (cubit) => cubit.cycleViewMode(),
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.previewOnly),
      ],
    );

    blocTest<NoteCreateCubit, NoteCreateState>(
      'cycleViewMode cycles through all modes',
      build: () => cubit,
      act: (cubit) {
        cubit.cycleViewMode(); // Split -> Preview
        cubit.cycleViewMode(); // Preview -> Edit
        cubit.cycleViewMode(); // Edit -> Split
      },
      expect: () => [
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.previewOnly),
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.editOnly),
        isA<NoteCreateEditing>()
            .having((s) => s.viewMode, 'viewMode', NoteViewMode.splitView),
      ],
    );

    test('createNoteFile returns null when name is invalid', () async {
      final file = await cubit.createNoteFile();
      expect(file, isNull);
    });

    test('createNoteFile creates IOFile with correct properties', () async {
      cubit.updateNoteName('Test Note');
      cubit.updateContent('# Test Content');

      final file = await cubit.createNoteFile();

      expect(file, isNotNull);
      expect(file!.name, 'Test Note.md');
      expect(file.contentType, 'text/markdown');

      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);
      expect(content, '# Test Content');
    });

    test('createNoteFile appends .md extension if not present', () async {
      cubit.updateNoteName('No Extension');

      final file = await cubit.createNoteFile();

      expect(file!.name, 'No Extension.md');
    });

    test('createNoteFile does not double-append .md extension', () async {
      cubit.updateNoteName('Already.md');

      final file = await cubit.createNoteFile();

      expect(file!.name, 'Already.md');
    });

    test('createNoteFile handles empty content', () async {
      cubit.updateNoteName('Empty Note');
      cubit.updateContent('');

      final file = await cubit.createNoteFile();

      expect(file, isNotNull);
      final bytes = await file!.readAsBytes();
      final content = String.fromCharCodes(bytes);
      expect(content, '');
    });

    test('createNoteFile handles unicode content', () async {
      cubit.updateNoteName('Unicode Note');
      cubit.updateContent('Hello 世界 🌍');

      final file = await cubit.createNoteFile();

      expect(file, isNotNull);
      final bytes = await file!.readAsBytes();
      final content = utf8.decode(bytes);
      expect(content, 'Hello 世界 🌍');
    });
  });
}
