import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';

abstract class GarRepository {
  Future<List<Gateway>> getGateways();
  List<Gateway> searchGateways(String query);
  Gateway getSelectedGateway();
  void updateGateway(Gateway gateway);
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
  Gateway getSelectedGateway() {
    final currentGatewayUrl =
        configService.config.defaultArweaveGatewayForDataRequest;
    final currentGatewayDomain = Uri.parse(currentGatewayUrl!).host;

    final currentGateway = _gateways.firstWhereOrNull(
      (gateway) => gateway.settings.fqdn == currentGatewayDomain,
    );

    return currentGateway!;
  }

  @override
  void updateGateway(Gateway gateway) {
    configService.updateAppConfig(
      configService.config.copyWith(
        defaultArweaveGatewayForDataRequest: 'https://${gateway.settings.fqdn}',
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
