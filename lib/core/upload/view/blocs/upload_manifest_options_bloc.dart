import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/utils/parse_assigned_names_from_string.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'upload_manifest_options_event.dart';
part 'upload_manifest_options_state.dart';

/// Outputs the selected manifest
/// with the corresponding names if any
class UploadManifestOptionsBloc
    extends Bloc<UploadManifestOptionsEvent, UploadManifestOptionsState> {
  final ARNSRepository arnsRepository;
  final ArDriveAuth arDriveAuth;

  final List<ManifestSelection> manifestFiles;
  final Set<String> _selectedManifestIds = {};
  final Set<String> _showingArNSSelection = {};
  Map<String, List<String>> reservedNames = {};

  List<ANTRecord>? _ants;

  UploadManifestOptionsBloc({
    required this.manifestFiles,
    required this.arnsRepository,
    required this.arDriveAuth,
    List<String>? selectedManifestIds,
  }) : super(UploadManifestOptionsReady(
          manifestFiles: Set.from(manifestFiles),
          selectedManifestIds: Set.from(selectedManifestIds ?? []),
          showingArNSSelection: const {},
          ants: null,
          reservedNames: const {},
          arnsNamesLoaded: false,
        )) {
    if (selectedManifestIds != null) {
      _selectedManifestIds.addAll(selectedManifestIds);

      final selectedManifests = selectedManifestIds
          .map((id) => manifestFiles.firstWhere((e) => e.manifest.id == id))
          .toList();

      for (var manifest in selectedManifests) {
        if (manifest.antRecord != null) {
          if (reservedNames[manifest.antRecord!.domain] == null) {
            reservedNames[manifest.antRecord!.domain] = [];
          }

          reservedNames[manifest.antRecord!.domain]!
              .add(manifest.undername?.name ?? '@');
        }
      }
    }

    on<LoadAnts>((event, emit) async {
      final walletAddress = await arDriveAuth.getWalletAddress();
      _ants = await arnsRepository.getAntRecordsForWallet(walletAddress!);

      for (var file in manifestFiles) {
        if (file.manifest.assignedNames != null &&
            file.manifest.assignedNames!.isNotEmpty) {
          final assignedNames =
              parseAssignedNamesFromString(file.manifest.assignedNames!);
          final assignedName = assignedNames!.first;

          final (domain, undername) = splitArNSRecordName(assignedName);

          /// For now, we only support adding one name
          final antRecord = _ants!.firstWhereOrNull((e) => e.domain == domain);

          if (antRecord != null) {
            try {
              final existingUndername = await arnsRepository
                  .getUndernameByDomainAndName(domain, undername ?? '@');

              add(SelectManifest(manifest: file.manifest));
              add(LinkManifestToUndername(
                manifest: file.manifest,
                antRecord: antRecord,
                undername: existingUndername,
              ));
            } catch (e) {
              logger.e('Error getting undername.', e);
            }
          }
        }
      }

      emit(_createReadyState());
    });

    on<SelectManifest>((event, emit) async {
      _selectedManifestIds.add(event.manifest.id);
      emit(_createReadyState());
    });

    on<DeselectManifest>((event, emit) {
      _selectedManifestIds.remove(event.manifest.id);
      _showingArNSSelection.remove(event.manifest.id);

      final indexOf =
          manifestFiles.indexWhere((e) => e.manifest.id == event.manifest.id);

      if (manifestFiles[indexOf].antRecord != null) {
        reservedNames[manifestFiles[indexOf].antRecord!.domain]!
            .remove(manifestFiles[indexOf].undername?.name ?? '@');

        manifestFiles[indexOf] = ManifestSelection(
          manifest: manifestFiles[indexOf].manifest,
        );
      }

      emit(_createReadyState());
    });

    on<ShowArNSSelection>((event, emit) async {
      _showingArNSSelection.add(event.manifest.id);

      emit(_createReadyState());
    });

    on<HideArNSSelection>((event, emit) {
      _showingArNSSelection.remove(event.manifest.id);
      emit(_createReadyState());
    });

    on<LinkManifestToUndername>((event, emit) {
      if (reservedNames[event.antRecord.domain] == null) {
        reservedNames[event.antRecord.domain] = [];
      }

      final indexOf =
          manifestFiles.indexWhere((e) => e.manifest.id == event.manifest.id);

      final manifest = manifestFiles[indexOf];

      if (manifest.antRecord != null) {
        reservedNames[manifest.antRecord!.domain]!
            .remove(manifest.undername?.name ?? '@');
      }

      manifestFiles[indexOf] = manifestFiles[indexOf].copyWith(
        antRecord: event.antRecord,
        undername: event.undername,
      );

      reservedNames[event.antRecord.domain]!.add(event.undername?.name ?? '@');
      _showingArNSSelection.remove(event.manifest.id);
      emit(_createReadyState());
    });
  }

  Future<List<ARNSUndername>> getARNSUndernames(
    ANTRecord antRecord,
  ) async {
    return arnsRepository.getARNSUndernames(antRecord);
  }

  UploadManifestOptionsReady _createReadyState() {
    return UploadManifestOptionsReady(
      manifestFiles: Set.from(manifestFiles),
      selectedManifestIds: Set.from(_selectedManifestIds),
      showingArNSSelection: Set.from(_showingArNSSelection),
      ants: _ants,
      reservedNames: reservedNames,
      arnsNamesLoaded: _ants != null,
    );
  }
}

class ManifestSelection extends Equatable {
  final FileEntry manifest;
  final ANTRecord? antRecord;
  final ARNSUndername? undername;

  const ManifestSelection({
    required this.manifest,
    this.antRecord,
    this.undername,
  });

  @override
  List<Object?> get props => [manifest, antRecord?.domain, undername?.name];

  ManifestSelection copyWith({
    ANTRecord? antRecord,
    ARNSUndername? undername,
  }) {
    return ManifestSelection(
        manifest: manifest, antRecord: antRecord, undername: undername);
  }
}
//
