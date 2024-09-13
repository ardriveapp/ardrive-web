import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/utils/arns_address_utils.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'assign_name_event.dart';
part 'assign_name_state.dart';

class AssignNameBloc extends Bloc<AssignNameEvent, AssignNameState> {
  final ARNSRepository _arnsRepository;
  final ArDriveAuth _auth;
  ARNSUndername? _selectedUndername;
  ANTRecord? _selectedANTRecord;

  AssignNameBloc({
    required ArDriveAuth auth,
    FileDataTableItem? fileDataTableItem,
    required ARNSRepository arnsRepository,
  })  : _auth = auth,
        _arnsRepository = arnsRepository,
        super(AssignNameInitial()) {
    on<LoadNames>((event, emit) async {
      emit(LoadingNames());

      final walletAddress = await _auth.getWalletAddress();

      final names = await _arnsRepository.getAntRecordsForWallet(walletAddress!);

      if (names.isEmpty) {
        emit(AssignNameEmptyState());
      } else {
        emit(NamesLoaded(names: names));
      }
    });

    on<SelectName>((event, emit) async {
      _selectedANTRecord = event.name;

      if (state is NamesLoaded) {
        emit(
          (state as NamesLoaded).copyWith(
            selectedName: event.name,
          ),
        );
      }
      if (state is UndernamesLoaded) {
        emit(
          NamesLoaded(
              names: (state as UndernamesLoaded).names,
              selectedName: _selectedANTRecord),
        );
      }
    });

    on<LoadUndernames>(
      (event, emit) async {
        final names = (state as NamesLoaded).names;
        emit(LoadingUndernames());

        final undernames =
            await _arnsRepository.getARNSUndernames(_selectedANTRecord!);

        if (undernames.length > 1) {
          undernames.removeWhere((element) => element.name == '@');
        }

        emit(
          UndernamesLoaded(
            selectedName: _selectedANTRecord!,
            names: names,
            undernames: undernames,
            selectedUndername: null,
          ),
        );
      },
    );

    on<SelectUndername>((event, emit) async {
      _selectedUndername = event.undername;

      if (state is UndernamesLoaded) {
        emit(
          (state as UndernamesLoaded).copyWith(
            selectedUndername: _selectedUndername,
          ),
        );
      }
    });

    on<ConfirmSelectionAndUpload>((event, emit) async {
      try {
        emit(ConfirmingSelection());
        try {
          if (fileDataTableItem == null) {
            throw StateError('File data table item is null');
          }

          ARNSUndername undername;

          if (_selectedUndername == null) {
            undername = ARNSUndername(
              name: '@',
              record: ARNSRecord(
                  transactionId: fileDataTableItem.dataTxId, ttlSeconds: 3600),
              domain: _selectedANTRecord!.domain,
            );
          } else {
            undername = ARNSUndername(
              name: _selectedUndername!.name,
              record: ARNSRecord(
                transactionId: fileDataTableItem.dataTxId,
                ttlSeconds: 3600,
              ),
              domain: _selectedANTRecord!.domain,
            );
          }

          await _arnsRepository.setUndernamesToFile(
            undername: undername,
            fileId: fileDataTableItem.fileId,
            driveId: fileDataTableItem.driveId,
            processId: _selectedANTRecord!.processId,
          );
        } catch (e) {
          logger.e('Failed to set ARNS', e);
        }

        final (address, arAddress) = getAddressesFromArns(
          domain: _selectedANTRecord!.domain,
          undername: _selectedUndername?.name,
        );

        emit(NameAssignedWithSuccess(
          address: address,
          arAddress: arAddress,
        ));
      } catch (e, stackTrace) {
        logger.e('Failed to confirm ArNS name assignment', e, stackTrace);
        emit(SelectionFailed());
      }
    });

    on<ConfirmSelection>((event, emit) async {
      emit(SelectionConfirmed(
        selectedName: _selectedANTRecord!,
        selectedUndername: _selectedUndername,
      ));
    });

    on<CloseAssignName>((event, emit) async {
      emit(EmptySelection());
    });
  }
}
