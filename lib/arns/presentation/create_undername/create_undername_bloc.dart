import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/domain/exceptions.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'create_undername_event.dart';
part 'create_undername_state.dart';

class CreateUndernameBloc
    extends Bloc<CreateUndernameEvent, CreateUndernameState> {
  final ARNSRepository _arnsRepository;
  final ArNSNameModel _nameModel;
  final String driveId;
  final String fileId;
  final String transactionId;
  CreateUndernameBloc(
    this._arnsRepository,
    this._nameModel,
    this.driveId,
    this.fileId,
    this.transactionId,
  ) : super(CreateUndernameInitial()) {
    on<CreateUndernameEvent>((event, emit) async {
      if (event is CreateNewUndername) {
        emit(CreateUndernameLoading());

        final ARNSUndername undername = ARNSUndernameFactory.create(
          name: event.name,
          transactionId: transactionId,
          domain: _nameModel.name,
        );

        try {
          logger.d('Creating undername...');
          await _arnsRepository.createUndername(undername: undername);
          logger.d('Undername created successfully');
          emit(CreateUndernameSuccess(nameModel: _nameModel));
        } on UndernameAlreadyExistsException {
          emit(CreateUndernameFailure(
              exception: UndernameAlreadyExistsException()));
        } catch (e, stacktrace) {
          logger.e('Error creating undername.', e, stacktrace);
          emit(CreateUndernameFailure(exception: e));
        }
      }
    });
  }
}
