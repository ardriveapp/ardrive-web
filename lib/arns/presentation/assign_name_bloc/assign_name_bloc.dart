import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'assign_name_event.dart';
part 'assign_name_state.dart';

class AssignNameBloc extends Bloc<AssignNameEvent, AssignNameState> {
  final ArioSDK _sdk;
  final ArDriveAuth _auth;
  final FileRepository _fileRepository;
  final FileDataTableItem _fileDataTableItem;
  final ARNSRepository _arnsRepository;

  ARNSUndername? _selectedUndername;
  ARNSRecord? _selectedARNSRecord;

  AssignNameBloc({
    required ArioSDK sdk,
    required ArDriveAuth auth,
    required FileRepository fileRepository,
    required FileDataTableItem fileDataTableItem,
    required ARNSRepository arnsRepository,
  })  : _sdk = sdk,
        _auth = auth,
        _fileRepository = fileRepository,
        _fileDataTableItem = fileDataTableItem,
        _arnsRepository = arnsRepository,
        super(AssignNameInitial()) {
    on<LoadNames>((event, emit) async {
      emit(LoadingNames());

      final names = await _sdk.getARNSRecords(_auth.getJWTAsString());

      await Future.delayed(const Duration(seconds: 1));

      emit(NamesLoaded(names: names));
    });

    on<SelectName>((event, emit) async {
      _selectedARNSRecord = event.name;

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
              selectedName: _selectedARNSRecord),
        );
      }
    });

    on<LoadUndernames>(
      (event, emit) async {
        final names = (state as NamesLoaded).names;
        emit(LoadingUndernames());

        final undernames = await _sdk.getUndernames(
            _auth.getJWTAsString(), _selectedARNSRecord!);

        emit(
          UndernamesLoaded(
            selectedName: _selectedARNSRecord!,
            names: names,
            undernames: undernames,
            selectedUndername: null,
          ),
        );
      },
    );

    on<SelectUndername>((event, emit) async {
      // if (!_selectedUndernames.contains(event.undername)) {
      //   _selectedUndernames.add(event.undername);
      // } else {
      //   logger.d('Removing ${event.undername.name}');

      //   _selectedUndernames.remove(event.undername);
      // }
      _selectedUndername = event.undername;

      emit(
        (state as UndernamesLoaded).copyWith(
          selectedUndername: _selectedUndername,
        ),
      );
    });

    on<ConfirmSelection>((event, emit) async {
      try {
        emit(ConfirmingSelection());
        try {
          ARNSUndername undername;

          if (_selectedUndername == null) {
            undername = ARNSUndername(
              name: '@',
              record: AntRecord(
                  transactionId: fileDataTableItem.dataTxId, ttlSeconds: 3600),
              domain: _selectedARNSRecord!.domain,
            );
          } else {
            undername = ARNSUndername(
                name: _selectedUndername!.name,
                record: AntRecord(
                  transactionId: fileDataTableItem.dataTxId,
                  ttlSeconds: 3600,
                ),
                domain: _selectedARNSRecord!.domain);
          }

          await _arnsRepository.setUndernamesToFile(
            undername: undername,
            fileId: fileDataTableItem.fileId,
            driveId: fileDataTableItem.driveId,
            processId: _selectedARNSRecord!.processId,
          );
        } catch (e) {
          logger.e('Failed to set ARNS', e);
        }

        String address = 'https://';

        if (_selectedUndername != null) {
          address = '$address${_selectedUndername!.name}_';
        }

        address = address + _selectedARNSRecord!.domain;
        address = '$address.ar-io.dev';

        emit(SelectionConfirmed(
          address: address,
        ));
      } catch (e) {
        logger.e('Failed to confirm selection', e);
        // emit(SelectionFailed());
        emit(SelectionConfirmed(
            address: 'https://arweave.net/${fileDataTableItem.dataTxId}'));
      }
    });

    on<ReviewSelection>((event, emit) async {
      emit(
        ReviewingSelection(
          domain: _selectedARNSRecord!.domain,
          undername: _selectedUndername!,
          txId: event.txId,
        ),
      );
    });
  }
}
