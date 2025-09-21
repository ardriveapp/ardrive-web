import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';

abstract class GarRepository {
  Future<List<Gateway>> getGateways();
  List<Gateway> searchGateways(String query);
  Future<Gateway> getSelectedGateway();
  Future<void> updateGateway(Gateway gateway);
  Future<bool> isGatewayActive(Gateway gateway);
}

class GarRepositoryImpl implements GarRepository {
  final ArioSDK arioSDK;
  final ConfigService configService;
  final ArweaveService arweave;
  final ArDriveHTTP http;

  GarRepositoryImpl({
    required this.arioSDK,
    required this.configService,
    required this.arweave,
    required this.http,
  });

  final List<Gateway> _gateways = [];

  @override
  Future<List<Gateway>> getGateways() async {
    _gateways.clear();
    _gateways.addAll(await arioSDK.getGateways());

    return _gateways;
  }

  @override
  Future<Gateway> getSelectedGateway() async {
    final currentGatewayUrl =
        configService.config.defaultArweaveGatewayForDataRequest;
    final currentGatewayDomain = Uri.parse(currentGatewayUrl.url).host;

    final currentGateway = _gateways.firstWhereOrNull(
      (gateway) {
        return gateway.settings.fqdn == currentGatewayDomain;
      },
    );

    /// if the gateway it not on the list of available gateways
    /// set the default the first one from the list.
    ///
    /// It can happen when the user change the gateway in the settings
    /// but the gateway is not available anymore.
    if (currentGateway == null) {
      /// Update the gateway in the config and the arweave gateway
      await updateGateway(_gateways.first);

      return _gateways.first;
    }

    return currentGateway;
  }

  @override
  Future<void> updateGateway(Gateway gateway) async {
    await configService.updateAppConfig(
      configService.config.copyWith(
        defaultArweaveGatewayForDataRequest: SelectedGateway(
          label: gateway.settings.label,
          url: 'https://${gateway.settings.fqdn}',
        ),
      ),
    );

    arweave.setGateway(gateway);
  }

  @override
  List<Gateway> searchGateways(String query) {
    final lowercaseQuery = query.toLowerCase();
    return _gateways.where((gateway) {
      final settings = gateway.settings;
      return settings.fqdn.toLowerCase().contains(lowercaseQuery) ||
          settings.label.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  @override
  Future<bool> isGatewayActive(Gateway gateway) async {
    try {
      final response = await http.getAsBytes(
        'https://${gateway.settings.fqdn}',
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
