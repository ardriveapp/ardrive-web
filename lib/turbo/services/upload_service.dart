import 'dart:async';

import 'package:ardrive/core/arconnect/safe_arconnect_action.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/data_item_utils.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/turbo_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:arweave/arweave.dart';
//import http
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class TurboUploadService {
  final bool useTurboUpload = true;
  final Uri turboUploadUri;
  final int allowedDataItemSize;
  ArDriveHTTP httpClient;
  final TabVisibilitySingleton _tabVisibility;

  TurboUploadService({
    required this.turboUploadUri,
    required this.allowedDataItemSize,
    required this.httpClient,
    required TabVisibilitySingleton tabVisibilitySingleton,
  }) : _tabVisibility = tabVisibilitySingleton;

  Stream<double> postDataItemWithProgress({
    required DataItem dataItem,
    required Wallet wallet,
  }) {
    final controller = StreamController<double>();

    controller.add(0);

    try {
      postDataItem(
        dataItem: dataItem,
        wallet: wallet,
        onSendProgress: (value) {
          controller.add(value);
          if (value == 1) {
            controller.close();
          }
        },
      ).then((value) {
        logger.i('Closing upload stream on UploadService for Turbo');
        controller.close();
      }).onError((error, stackTrace) {
        logger.e(
            'Catching error in postDataItemWithProgress', error, stackTrace);
        controller.addError(error ?? Exception('Error'));
        logger.e('Closing stream');
        controller.close();
      });
    } catch (e) {
      logger.e('Catching an uncaught error on UploadService', e);
      controller.addError(e);
      logger.e('Closing stream');
      controller.close();
    }

    return controller.stream;
  }

  Future<void> postDataItemStream({
    required Stream<List<int>> dataItemStream,
    required Wallet wallet,
    Function(double)? onSendProgress,
  }) async {
    try {
      final acceptedStatusCodes = [200, 202, 204];

      final nonce = const Uuid().v4();
      final publicKey = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Getting public key with safe ArConnect action');
          return wallet.getOwner();
        },
      );
      final signature = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Signing with safe ArConnect action');
          return signNonceAndData(
            nonce: nonce,
            wallet: wallet,
          );
        },
      );

      final headers = {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      };

      final url = '$turboUploadUri/v1/tx';
      const receiveTimeout = Duration(days: 365);
      const sendTimeout = Duration(days: 365);

      // if (AppPlatform.isMobile) {
      //   final response = await httpClient.postBytes(
      //     url: url,
      //     onSendProgress: onSendProgress,
      //     data: (await dataItem.asBinary()).toBytes(),
      //     headers: headers,
      //     receiveTimeout: receiveTimeout,
      //     sendTimeout: sendTimeout,
      //   );

      //   if (!acceptedStatusCodes.contains(response.statusCode)) {
      //     logger.e('Error posting bytes', response.data);
      //     throw _handleException(response);
      //   }
      //   return;
      // }

      final response = await httpClient.postBytesAsStream(
        url: url,
        onSendProgress: (progress) {
          logger.d('Progress: $progress');
          // onSendProgress?.call(progress);
        },
        headers: headers,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
        data: dataItemStream,
      );

      logger.d('Response from turbo: ${response.statusCode}');

      if (!acceptedStatusCodes.contains(response.statusCode)) {
        logger.e('Error posting bytes', response.data);
        throw _handleException(response);
      }
    } catch (e, stacktrace) {
      logger.e('Catching error in postDataItem', e, stacktrace);
      throw _handleException(e);
    }
  }

  Future<void> postDataItemStreamOldHttp({
    required Stream<List<int>> dataItemStream,
    required Wallet wallet,
    Function(double)? onSendProgress,
  }) async {
    try {
      final acceptedStatusCodes = [200, 202, 204];

      final nonce = const Uuid().v4();
      final publicKey = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Getting public key with safe ArConnect action');
          return wallet.getOwner();
        },
      );
      final signature = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Signing with safe ArConnect action');
          return signNonceAndData(
            nonce: nonce,
            wallet: wallet,
          );
        },
      );

      final headers = {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      };

      final url = '$turboUploadUri/v1/tx';
      const receiveTimeout = Duration(days: 365);
      const sendTimeout = Duration(days: 365);

      // if (AppPlatform.isMobile) {
      //   final response = await httpClient.postBytes(
      //     url: url,
      //     onSendProgress: onSendProgress,
      //     data: (await dataItem.asBinary()).toBytes(),
      //     headers: headers,
      //     receiveTimeout: receiveTimeout,
      //     sendTimeout: sendTimeout,
      //   );

      //   if (!acceptedStatusCodes.contains(response.statusCode)) {
      //     logger.e('Error posting bytes', response.data);
      //     throw _handleException(response);
      //   }
      //   return;
      // }

      var request = http.Request('POST', Uri.parse(url));
      request.headers.addAll(headers);

      request.bodyBytes = await dataItemStream.reduce((a, b) => a + b);

      var response = await request.send();
      if (response.statusCode == 200) {
        print('Success');
      } else {
        print('Error: ${response.reasonPhrase}');
      }

      logger.d('Response from turbo: ${response.statusCode}');

      if (!acceptedStatusCodes.contains(response.statusCode)) {
        logger.e('Error posting bytes', response.contentLength);
        throw _handleException(response);
      }
    } catch (e, stacktrace) {
      logger.e('Catching error in postDataItem', e, stacktrace);
      throw _handleException(e);
    }
  }

  Future<void> uploadLargeStream(
      Stream<List<int>> byteStream, Wallet wallet, int size) async {
    final nonce = const Uuid().v4();

    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        logger.d('Getting public key with safe ArConnect action');
        return wallet.getOwner();
      },
    );

    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        logger.d('Signing with safe ArConnect action');
        return signNonceAndData(
          nonce: nonce,
          wallet: wallet,
        );
      },
    );

    // logger.d('Uploading to $turboUploadUri/v1/tx');
    // var request =
    //     http.StreamedRequest('PUT', Uri.parse('$turboUploadUri/v1/tx'));
    // request.headers.addAll({
    //   'x-nonce': nonce,
    //   'x-signature': signature,
    //   'x-public-key': publicKey,
    // });

    // byteStream.listen((event) {
    //   logger.d('Sending chunk of size ${event.length}');
    //   request.sink.add(event);
    // }, onDone: () {
    //   logger.d('Closing request');
    //   request.sink.close();
    // });

    // request.send().then((response) {
    //   if (response.statusCode == 200) print('Uploaded!');
    //   print(response.statusCode);
    // }).catchError((e) {
    //   print(e.toString());
    // });
    final url = '$turboUploadUri/v1/tx';
    final request = http.MultipartRequest('POST', Uri.parse(url));

    final length = size;

    final multipartFile =
        http.MultipartFile('file', byteStream, length, filename: 'myfile.txt');
    request.files.add(multipartFile);

    final response = await request.send();

    if (response.statusCode == 200) {
      print('Upload successful.');
    } else {
      print('Upload failed.');
    }
  }

  Future<void> postWithHttp({
    required DataItemResult dataItem,
    required Wallet wallet,
  }) async {
    final url = '$turboUploadUri/v1/tx';
    logger.d('Posting with http');

    final nonce = const Uuid().v4();

    final publicKey = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        logger.d('Getting public key with safe ArConnect action');
        return wallet.getOwner();
      },
    );

    final signature = await safeArConnectAction<String>(
      _tabVisibility,
      (_) async {
        logger.d('Signing with safe ArConnect action');
        return signNonceAndData(
          nonce: nonce,
          wallet: wallet,
        );
      },
    );

    final headers = {
      'x-nonce': nonce,
      'x-signature': signature,
      'x-public-key': publicKey,
    };

    // final client = FetchClient(
    //   mode: RequestMode.cors,
    //   streamRequests: true,
    // );

    // final request = StreamedRequest('POST', Uri.parse(url))
    //   ..headers.addAll(headers);

    // dataItem.streamGenerator().listen(
    //       request.sink.add,
    //       onDone: request.sink.close,
    //       onError: request.sink.addError,
    //     );

    // final response = await client.send(request);

    // logger.d('Response from turbo: ${response.statusCode}');
    int chunkNumber = 0;
    int uploadedBytes = 0;

    final streamedRequest = http.StreamedRequest('POST', Uri.parse(url))
      ..headers.addAll(headers);
    streamedRequest.contentLength = dataItem.dataItemSize;
    dataItem.streamGenerator().listen((chunk) async {
      chunkNumber++;
      logger.d(chunk.length.toString());
      logger.d('Sending chunk $chunkNumber');
      logger.d('Uploaded bytes: $uploadedBytes');
      streamedRequest.sink.add(chunk);
      uploadedBytes += chunk.length;
      if (uploadedBytes == dataItem.dataItemSize) {
        logger.d('Uploaded all bytes');
        streamedRequest.sink.close();
        return;
      }
    }, onDone: () async {});

    final response = await streamedRequest.send();

    logger.d('Response from turbo: ${response.statusCode}');

    final bytesList = await response.stream.toBytes();

    logger.d('Response bytes: ${String.fromCharCodes(bytesList)}');

    logger.d('sent request');

    // final client = FetchClient(
    //   streamRequests: true,
    // );

    // final request = StreamedRequest('POST', Uri.parse(url))
    //   ..headers.addAll(headers)
    //   ..contentLength = dataItem.dataItemSize;

    // logger.d(request.contentLength?.toString() ?? 'No content length');

    // dataItem.streamGenerator().listen(
    //       request.sink.add,
    //       onDone: request.sink.close,
    //       onError: request.sink.addError,
    //     );

    // final response = await client.send(request);

    // logger.d('Response from turbo: ${response.statusCode}');

    // final stream = callConstructor(
    //   getProperty(window, 'ReadableStream'),
    //   [
    //     jsify({
    //       'start': (controller) {
    //         dataItem.streamGenerator().listen(
    //           (data) {
    //             callMethod(controller, 'enqueue', [data]);
    //           },
    //           onError: (e) {
    //             callMethod(controller, 'error', [e]);
    //           },
    //           onDone: () {
    //             callMethod(controller, 'close', []);
    //           },
    //         );
    //       }
    //     }),
    //   ],
    // );

    // try {
    //   final response = await window.fetch(
    //     url,
    //     {
    //       'method': 'POST',
    //       headers: jsify(headers),
    //       'body': stream,
    //     },
    //     // RequestInit(
    //     //   method: 'POST',
    //     //   headers: headers,
    //     //   body: controller.stream,
    //     // ),
    //   );

    //   if (response.ok) {
    //     final responseBody = await response.text();
    //     print('Received response: $responseBody');
    //   } else {
    //     print('Failed to upload data. Status code: ${response.status}');
    //   }
    // } catch (e) {
    //   print('An error occurred: $e');
    // }

    // request.headers.addAll(headers);

    // logger.d('Sending request');

    // final response = request.send();

    // await for (var value in dataItem.streamGenerator()) {
    //   request.sink.add(value);
    // }

    // request.sink.close();

    // await response.then((value) {
    //   logger.d('Response from turbo: ${value.statusCode}');
    // });
  }

  Future<void> postDataItem({
    required DataItem dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
  }) async {
    try {
      final acceptedStatusCodes = [200, 202, 204];

      final nonce = const Uuid().v4();
      final publicKey = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Getting public key with safe ArConnect action');
          return wallet.getOwner();
        },
      );
      final signature = await safeArConnectAction<String>(
        _tabVisibility,
        (_) async {
          logger.d('Signing with safe ArConnect action');
          return signNonceAndData(
            nonce: nonce,
            wallet: wallet,
          );
        },
      );

      final headers = {
        'x-nonce': nonce,
        'x-signature': signature,
        'x-public-key': publicKey,
      };

      final url = '$turboUploadUri/v1/tx';
      const receiveTimeout = Duration(days: 365);
      const sendTimeout = Duration(days: 365);

      if (AppPlatform.isMobile) {
        final response = await httpClient.postBytes(
          url: url,
          onSendProgress: onSendProgress,
          data: (await dataItem.asBinary()).toBytes(),
          headers: headers,
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        );

        if (!acceptedStatusCodes.contains(response.statusCode)) {
          logger.e('Error posting bytes', response.data);
          throw _handleException(response);
        }
        return;
      }

      final response = await httpClient.postBytesAsStream(
          url: url,
          onSendProgress: onSendProgress,
          headers: headers,
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
          data: await convertDataItemToStreamBytes(dataItem));

      if (!acceptedStatusCodes.contains(response.statusCode)) {
        logger.e('Error posting bytes', response.data);
        throw _handleException(response);
      }
    } catch (e) {
      logger.e('Catching error in postDataItem', e);
      throw _handleException(e);
    }
  }

  Exception _handleException(Object error) {
    logger.e('Handling exception in UploadService', error);

    if (error is ArDriveHTTPResponse && error.statusCode == 408) {
      logger.e(
        'Handling exception in UploadService with status code: ${error.statusCode}',
        error,
      );

      return TurboUploadTimeoutException();
    }
    if (error is ArDriveHTTPException && error.statusCode == 408) {
      logger.e(
        'Handling exception in UploadService with status code: ${error.statusCode}',
        error,
      );

      return TurboUploadTimeoutException();
    }

    return Exception(error);
  }
}

class DontUseUploadService implements TurboUploadService {
  @override
  int get allowedDataItemSize => throw UnimplementedError();

  @override
  Future<void> postDataItem({
    required DataItem dataItem,
    required Wallet wallet,
    Function(double)? onSendProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Uri get turboUploadUri => throw UnimplementedError();

  @override
  bool get useTurboUpload => false;

  @override
  late ArDriveHTTP httpClient;

  @override
  Stream<double> postDataItemWithProgress(
      {required DataItem dataItem, required Wallet wallet}) {
    // TODO: implement postDataItemWithProgress
    throw UnimplementedError();
  }

  @override
  TabVisibilitySingleton get _tabVisibility => throw UnimplementedError();

  @override
  Exception _handleException(Object error) {
    // TODO: implement _handleException
    throw UnimplementedError();
  }

  @override
  Future<void> postDataItemStream(
      {required Stream<List<int>> dataItemStream,
      required Wallet wallet,
      Function(double p1)? onSendProgress}) {
    // TODO: implement postDataItem2
    throw UnimplementedError();
  }

  @override
  Future<void> postDataItemStreamOldHttp(
      {required Stream<List<int>> dataItemStream,
      required Wallet wallet,
      Function(double p1)? onSendProgress}) {
    // TODO: implement postDataItemStreamOldHttp
    throw UnimplementedError();
  }

  @override
  Future<void> uploadLargeStream(
      Stream<List<int>> byteStream, Wallet wallet, int size) {
    // TODO: implement uploadLargeStream
    throw UnimplementedError();
  }

  @override
  Future<void> postWithHttp(
      {required DataItemResult dataItem, required Wallet wallet}) {
    // TODO: implement postWithHttp
    throw UnimplementedError();
  }
}

class TurboUploadExceptions implements Exception {}

class TurboUploadTimeoutException implements TurboUploadExceptions {}
