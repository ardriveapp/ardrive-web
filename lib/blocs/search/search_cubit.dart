import 'dart:async';

import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:moor/moor.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/url_launcher.dart';

import '../blocs.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<DriveDetailState> {
  late FormGroup form;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final AppConfig _config;

  final _defaultAvailableRowsPerPage = [25, 50, 75, 100];

  SearchCubit({
    String? initialFolderId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required AppConfig config,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _config = config,
        super(DriveDetailLoadInProgress()) {
    form = FormGroup(
      {
        'search': FormControl<String>(
          // Debounce drive name loading by 500ms.
          asyncValidatorsDebounceTime: 500,
        ),
      },
    );
  }

  void searchFolder({
    String search = '',
  }) async {
    emit(DriveDetailLoadInProgress());
    final searchResults =
        _driveDao.allFiles().map((file) => file.name.contains(search)).get();
  }

  List<int> calculateRowsPerPage(int totalEntries) {
    List<int> availableRowsPerPage;
    if (totalEntries < _defaultAvailableRowsPerPage.first) {
      availableRowsPerPage = <int>[totalEntries];
    } else {
      availableRowsPerPage = _defaultAvailableRowsPerPage;
    }
    return availableRowsPerPage;
  }

  void setRowsPerPage(int rowsPerPage) {
    switch (state.runtimeType) {
      case DriveDetailLoadSuccess:
        emit(
          (state as DriveDetailLoadSuccess).copyWith(
            rowsPerPage: rowsPerPage,
          ),
        );
    }
  }

  Future<void> selectItem(SelectedItem selectedItem) async {
    var state = this.state as DriveDetailLoadSuccess;

    state = state.copyWith(maybeSelectedItem: selectedItem);
    if (state.currentDrive.isPublic && selectedItem is SelectedFile) {
      final fileWithRevisions = _driveDao.latestFileRevisionByFileId(
        driveId: selectedItem.item.driveId,
        fileId: selectedItem.id,
      );
      final dataTxId = (await fileWithRevisions.getSingle()).dataTxId;
      state = state.copyWith(
          selectedFilePreviewUrl:
              Uri.parse('${_config.defaultArweaveGatewayUrl}/$dataTxId'));
    }

    emit(state);
  }

  Future<void> launchPreview(TxID dataTxId) {
    return launch('${_config.defaultArweaveGatewayUrl}/$dataTxId');
  }

  void sortSearchResuls({
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) {
    final state = this.state as DriveDetailLoadSuccess;
  }

  void submit() async {
    form.markAllAsTouched();

    try {
      final String search = form.control('search').value;
      //searchFolder(search: search);
    } catch (err) {
      addError(err);
    }
  }

  void toggleSelectedItemDetails() {
    final state = this.state as DriveDetailLoadSuccess;
    emit(state.copyWith(
        showSelectedItemDetails: !state.showSelectedItemDetails));
  }
}
