import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

List<int> retryStatusCodes = [
  408,
  429,
  440,
  460,
  499,
  500,
  502,
  503,
  504,
  520,
  521,
  522,
  523,
  524,
  525,
  527,
  598,
  599
];

Future<void> main() async {
  Router app = Router();

  app.get(
    '/getJson',
    (Request request) => Response.ok(
      JsonEncoder.withIndent(' ').convert({'message': 'ok'}),
      headers: {
        'content-type': 'application/json',
        'access-control-allow-origin': '*',
      },
    ),
  );

  retryStatusCodes.forEach((code) {
    app.get(
      '/$code',
      (Request request) => Response(code, headers: {
        'access-control-allow-origin': '*',
      }),
    );
  });

  app.get(
    '/404',
    (Request request) => Response(404, headers: {
      'access-control-allow-origin': '*',
    }),
  );

  final server = await shelf_io.serve(
    app,
    InternetAddress.anyIPv4, // Allows external connections
    8080,
  );

  print('Serving at http://${server.address.host}:${server.port}');
}
