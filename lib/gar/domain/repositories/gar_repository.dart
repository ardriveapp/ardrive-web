import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';

abstract class GarRepository {
  Future<List<Gateway>> getGateways();
  List<Gateway> searchGateways(String query);
  Gateway getSelectedGateway();
  void updateGateway(Gateway gateway);
}

class GarRepositoryImpl implements GarRepository {
  final ArioSDK arioSDK;
  final ConfigService configService;
  final ArweaveService arweave;

  GarRepositoryImpl({
    required this.arioSDK,
    required this.configService,
    required this.arweave,
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
    final gateways = _gateways
        .where(
          (gateway) => gateway.settings.fqdn.contains(query),
        )
        .toList();

    return gateways;
  }
}
