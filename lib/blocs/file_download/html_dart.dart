import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:rxdart/rxdart.dart';

class DownloadProgress extends LinearProgress {
  DownloadProgress(
      {required this.loaded,
      required this.total,
      this.speed,
      this.remainingTime});

  factory DownloadProgress.initial(int totalBytes) =>
      DownloadProgress(loaded: 0, total: totalBytes);

  int loaded;
  int total;
  double? speed;
  int? remainingTime;
  @override
  double get progress => loaded / total;
}

final downloadController = StreamController<DownloadProgress>.broadcast();

final downloadStream = downloadController.stream;

Future<List<int>> downloadProgress(String tx, ArweaveService arweave) async {
  // This is for Flutter Web
  final httpReq = HttpRequest();

  late DownloadProgress downloadProgress;

  print('Start request');
  final start = DateTime.now();

  httpReq.open(
    'GET',
    arweave.client.api.gatewayUrl.origin + '/$tx',
  );
  httpReq.onLoadStart.listen((event) {
    // downloadProgress = DownloadProgress.initial(event.total!);
    // downloadController.add(downloadProgress);
  });

  httpReq.onProgress.debounceTime(Duration(milliseconds: 50)).listen((event) {
    if (event.total == 0 || event.total == null) {
      return;
    }
    print('On progress event');
    print((event.loaded! / event.total!).toString());

    final speed = event.loaded! /
        DateTime.now().difference(start).inSeconds /
        (1024 * 1000);

    downloadProgress = DownloadProgress(
        loaded: event.loaded!, total: event.total!, speed: speed);
    downloadProgress.remainingTime =
        (event.total! - event.loaded!) ~/ speed ~/ (1024 * 1000);

    downloadController.sink.add(downloadProgress);
  });

  httpReq.onLoad.listen((event) {
    print('on load event');
  });

  httpReq.onLoadEnd.listen((event) {
    print('On load end callback');
  });

  httpReq.onError.listen((event) {});
  // httpReq.overrideMimeType('application/octet-stream; charset=x-user-defined');
  httpReq.responseType = 'arraybuffer';
  httpReq.send();
  // Future.delayed(Duration(seconds: 5)).then((value) => httpReq.abort());

  await httpReq.onLoadEnd
      .isEmpty; // this is to block the code from going forward until httpReq is done

  final response = httpReq.response as ByteBuffer;

  print('response type ${httpReq.responseType}');

  return response.asInt8List();
}
