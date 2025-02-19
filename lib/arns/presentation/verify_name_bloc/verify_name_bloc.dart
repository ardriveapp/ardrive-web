import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'verify_name_event.dart';
part 'verify_name_state.dart';

class VerifyNameBloc extends Bloc<VerifyNameEvent, VerifyNameState> {
  final ARNSRepository _arnsRepository;

  VerifyNameBloc({
    required ARNSRepository arnsRepository,
  })  : _arnsRepository = arnsRepository,
        super(VerifyNameInitial()) {
    on<VerifyName>(_onVerifyName);
  }

  Future<void> _onVerifyName(
    VerifyName event,
    Emitter<VerifyNameState> emit,
  ) async {
    try {
      emit(VerifyNameLoading());

      final activeARNSRecords =
          await _arnsRepository.getActiveARNSRecordsForFile(event.fileId);

      if (activeARNSRecords.isEmpty) {
        emit(VerifyNameEmpty());
        return;
      }

      final undername = activeARNSRecords.last;
      emit(VerifyNameSuccess(undername: undername));
    } catch (e, stackTrace) {
      logger.e('Failed to verify ArNS name', e, stackTrace);
      emit(VerifyNameFailure());
    }
  }
}
