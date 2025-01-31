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
  // TODO: remove this later
  ArNSNameModel? _selectedNameModel;

  AssignNameBloc({
    required ArDriveAuth auth,
    FileDataTableItem? fileDataTableItem,
    required ARNSRepository arnsRepository,
  })  : _auth = auth,
        _arnsRepository = arnsRepository,
        super(AssignNameInitial()) {
    on<LoadNames>(
      (event, emit) async {
        try {
          logger.d('Loading names');
          emit(LoadingNames());

          final walletAddress = await _auth.getWalletAddress();

          final names = await _arnsRepository
              .getAntRecordsForWallet(walletAddress!, update: false);

          final nameModels =
              await _arnsRepository.getARNSNameModelsForWallet(walletAddress);

          if (names.isEmpty) {
            emit(AssignNameEmptyState());
          } else {
            logger.d('Names loaded');
            emit(NamesLoaded(nameModels: nameModels));
          }
        } catch (e) {
          logger.e('Failed to load ArNS names', e);
          emit(LoadingNamesFailed());
        }
      },
    );

    on<SelectName>((event, emit) async {
      if (state is NamesLoaded) {
        emit(
          (state as NamesLoaded).copyWith(
            selectedName: event.nameModel,
          ),
        );
      }

      if (state is UndernamesLoaded &&
          _selectedNameModel?.name == event.nameModel.name) {
        emit(
          NamesLoaded(
            nameModels: (state as UndernamesLoaded).nameModels,
            selectedName: _selectedNameModel,
          ),
        );
      }

      _selectedNameModel = event.nameModel;
    });

    on<LoadUndernames>(
      (event, emit) async {
        if (state is UndernamesLoaded) {
          final undernames = await _arnsRepository.getARNSUndernames(
            ANTRecord(
              domain: _selectedNameModel!.name,
              processId: _selectedNameModel!.processId,
            ),
          );

          if (undernames.length > 1) {
            undernames.removeWhere((element) => element.name == '@');
          }

          emit(
            UndernamesLoaded(
              nameModels: (state as UndernamesLoaded).nameModels,
              selectedName: _selectedNameModel!,
              undernames: undernames,
              selectedUndername: null,
            ),
          );

          return;
        }

        final names = (state as NamesLoaded).nameModels;
        emit(LoadingUndernames());

        final undernames = await _arnsRepository.getARNSUndernames(
          ANTRecord(
            domain: _selectedNameModel!.name,
            processId: _selectedNameModel!.processId,
          ),
        );

        if (undernames.length > 1) {
          undernames.removeWhere((element) => element.name == '@');
        }

        emit(
          UndernamesLoaded(
            nameModels: names,
            selectedName: _selectedNameModel!,
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
        if (fileDataTableItem == null) {
          throw StateError('File data table item is null');
        }

        ARNSUndername undername;

        if (_selectedUndername == null) {
          undername = ARNSUndernameFactory.createDefaultUndername(
            transactionId: fileDataTableItem.dataTxId,
            domain: _selectedNameModel!.name,
          );
        } else {
          undername = ARNSUndernameFactory.create(
            name: _selectedUndername!.name,
            transactionId: fileDataTableItem.dataTxId,
            domain: _selectedNameModel!.name,
          );
        }

        await _arnsRepository.setUndernamesToFile(
          undername: undername,
          fileId: fileDataTableItem.fileId,
          driveId: fileDataTableItem.driveId,
          processId: _selectedNameModel!.processId,
        );

        final (address, arAddress) = getAddressesFromArns(
          domain: _selectedNameModel!.name,
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

    on<ShowSuccessModal>((event, emit) async {
      final (address, arAddress) = getAddressesFromArns(
        domain: event.undername.domain,
        undername: event.undername.name,
      );

      emit(NameAssignedWithSuccess(
        address: address,
        arAddress: arAddress,
      ));
    });

    on<ConfirmSelection>((event, emit) async {
      logger.d('ConfirmSelection');
      logger.d('selectedNameModel: ${_selectedNameModel}');
      logger.d('selectedUndername: ${_selectedUndername}');

      emit(SelectionConfirmed(
        selectedName: _selectedNameModel!,
        selectedUndername: _selectedUndername,
      ));
    });

    on<CloseAssignName>((event, emit) async {
      emit(EmptySelection());
    });
  }
}
