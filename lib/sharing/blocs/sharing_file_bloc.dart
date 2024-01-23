import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:share_plus/share_plus.dart';

part 'sharing_file_event.dart';
part 'sharing_file_state.dart';

class SharingFileBloc extends Bloc<SharingFileEvent, SharingFileState> {
  List<SharedFile>? files;

  SharingFileBloc() : super(SharingFileInitial()) {
    // For sharing images coming from outside the app while the app is in the memory

    // For sharing images coming from outside the app while the app is closed
    FlutterSharingIntent.instance
        .getInitialSharing()
        .then((List<SharedFile> value) {
      if (value.isNotEmpty) {
        add(SharingFileReceived(value));
      }
    });

    // For sharing images coming from outside the app while the app is in the memory
    FlutterSharingIntent.instance.getMediaStream().listen((event) {
      add(SharingFileReceived(event));
    });

    on<SharingFileEvent>((event, emit) async {
      if (event is SharingFileReceived) {
        files = event.files;
        final ioFiles = <IOFile>[];

        IOFileAdapter ioFileAdapter = IOFileAdapter();

        for (final file in files!) {
          ioFiles.add(await ioFileAdapter.fromXFile(XFile(file.value!)));
        }

        emit(SharingFileReceivedState(ioFiles));
      } else if (event is SharingFileCleared) {
        files = null;
      } else if (event is ShowSharingFile) {
        // emit(SharingFileReceivedState(files!));
      }
    });
  }
}
