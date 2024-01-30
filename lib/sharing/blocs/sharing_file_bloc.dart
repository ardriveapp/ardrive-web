import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/utils/logger.dart';
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
  final ActivityTracker activityTracker;

  SharingFileBloc(
    this.activityTracker,
  ) : super(SharingFileInitial()) {
    FlutterSharingIntent.instance
        .getInitialSharing()
        .then((List<SharedFile> value) {
      logger.d('SharingFileReceived');

      if (value.isNotEmpty) {
        add(SharingFileReceived(value));
      }
    });

    FlutterSharingIntent.instance.getMediaStream().listen((value) {
      logger.d('SharingFileReceived');

      if (value.isNotEmpty) {
        add(SharingFileReceived(value));
      }
    });

    on<SharingFileEvent>((event, emit) async {
      if (event is SharingFileReceived) {
        activityTracker.setSharingFilesFromExternalApp(true);
        files = event.files;
        final ioFiles = <IOFile>[];

        IOFileAdapter ioFileAdapter = IOFileAdapter();

        for (final file in files!) {
          ioFiles.add(await ioFileAdapter.fromXFile(XFile(file.value!)));
        }

        emit(SharingFileReceivedState(ioFiles));
      } else if (event is SharingFileCleared) {
        files = null;
        activityTracker.setSharingFilesFromExternalApp(false);
        emit(
            SharingFileClearedState()); // Emit a new state indicating that files are cleared
      }
    });
  }

  @override
  close() async {
    activityTracker.setSharingFilesFromExternalApp(false);
    super.close();
  }
}
