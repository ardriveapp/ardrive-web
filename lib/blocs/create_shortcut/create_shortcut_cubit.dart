import 'dart:developer';

import 'package:ardrive/blocs/create_shortcut/create_shortcut_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:reactive_forms/reactive_forms.dart';

class CreateShortcutCubit extends Cubit<CreateShortcutState> {
  CreateShortcutCubit() : super(CreateShortcutInitial());

  final form = FormGroup(
    {
      'shortcut': FormControl<String>(
        validators: [Validators.required],
        asyncValidatorsDebounceTime: 500,
      ),
    },
  );

  Future<void> isValid() async {
    try {
      emit(CreateShortcutLoading());
      final txId = form.control('shortcut').value;
      final header =
          await http.head(Uri.parse('https://arweave.net/raw/$txId'));
      log(header.body);
      emit(CreateShortcutSuccess());
    } catch (e) {
      emit(CreateShortcutError());
    }
  }
}
