import 'package:ario_sdk/ario_sdk.dart';

/// Returns the URI of the given [gateway].
///
Uri getGatewayUri(Gateway gateway) {
  return Uri(
    scheme: gateway.settings.protocol,
    host: gateway.settings.fqdn,
    port: gateway.settings.port,
  );
}
