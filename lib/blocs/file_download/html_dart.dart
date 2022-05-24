import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';

Future<List<int>> downloadProgress(String tx, ArweaveService arweave) async {
  // Map<String, String> body = {'test': 'tegffgst'};

  // This is for Flutter Web
  final httpReq = HttpRequest();
  // final request = await HttpRequest.request(
  //     arweave.client.api.gatewayUrl.origin + '/$tx',
  //     method: 'GET', onProgress: (progress) {
  //   print('progress');
  // });
  // print(request.response!);

  var parts = [];
  // body.forEach((key, value) {
  //   parts.add('${Uri.encodeQueryComponent(key)}='
  //       '${Uri.encodeQueryComponent(value)}');
  // });
  // var data = parts.join('&');
  var res;

  print('Start request');

  httpReq.open(
    'GET',
    arweave.client.api.gatewayUrl.origin + '/$tx',
  );
  final buffer = <int>[];
  httpReq.onProgress.listen((event) {
    print('On progress event');
    // print(httpReq.responseText?.length);
    print(httpReq.responseText as ByteBuffer);
    print((event.loaded! / event.total!).toString());
  });

  httpReq.onLoad.listen((event) {
    print('on load event');
  });

  httpReq.onLoadEnd.listen((event) {
    print('On load end callback');
  });
  httpReq.onError.listen((event) {});
  // httpReq.overrideMimeType('text/plain; charset=x-user-defined');
  httpReq.responseType = 'arraybuffer';
  httpReq.send();

  await httpReq.onLoadEnd
      .isEmpty; // this is to block the code from going forward until httpReq is done

  final response = httpReq.response as ByteBuffer;

  print('response type ${httpReq.responseType}');

  return response.asInt8List();
}
