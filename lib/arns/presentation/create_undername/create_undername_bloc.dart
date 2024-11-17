import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

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

        final ARNSUndername undername = ARNSUndername(
          name: event.name,
          record: ARNSRecord(
            transactionId: transactionId,
            ttlSeconds: 3600,
          ),
          domain: _nameModel.name,
        );

        logger.d('Process ID: ${_nameModel.processId}');
        await _arnsRepository.setUndernamesToFile(
          undername: undername,
          driveId: driveId,
          fileId: fileId,
          processId: _nameModel.processId,
        );

        logger.d('Creating new undername: ${event.name}');

        emit(CreateUndernameSuccess(undername: undername));
      }
    });
  }
}
