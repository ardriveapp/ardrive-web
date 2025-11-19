import 'package:ardrive/gar/utils/gateway_validator.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';

abstract class GarRepository {
  Future<List<Gateway>> getGateways();
  List<Gateway> searchGateways(String query);
  Future<Gateway> getSelectedGateway();
  Future<void> updateGateway(Gateway gateway);
  Future<bool> isGatewayActive(Gateway gateway);
  
  // Custom gateway methods
  Future<GatewayValidationResult> validateCustomGateway(String gatewayUrl);
  Future<void> updateCustomGateway(String gatewayUrl);
  bool isValidGatewayUrl(String url);
  String cleanGatewayUrl(String url);
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
    final newGatewayUrl = 'https://${gateway.settings.fqdn}';
    logger.i('Gateway updated to: $newGatewayUrl (${gateway.settings.label})');

    await configService.updateAppConfig(
      configService.config.copyWith(
        defaultArweaveGatewayForDataRequest: SelectedGateway(
          label: gateway.settings.label,
          url: newGatewayUrl,
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

  @override
  Future<GatewayValidationResult> validateCustomGateway(String gatewayUrl) async {
    return await GatewayValidator.validateGateway(gatewayUrl);
  }

  @override
  Future<void> updateCustomGateway(String gatewayUrl) async {
    final cleanedUrl = cleanGatewayUrl(gatewayUrl);
    logger.i('Custom gateway updated to: $cleanedUrl');

    await configService.updateAppConfig(
      configService.config.copyWith(
        defaultArweaveGatewayForDataRequest: SelectedGateway(
          label: GatewayValidator.generateLabel(cleanedUrl),
          url: cleanedUrl,
        ),
      ),
    );

    // Create a custom Gateway object for ArweaveService
    final customGateway = _createCustomGateway(cleanedUrl);
    arweave.setGateway(customGateway);
  }

  @override
  bool isValidGatewayUrl(String url) {
    return GatewayValidator.isValidUrl(url);
  }

  @override
  String cleanGatewayUrl(String url) {
    return GatewayValidator.cleanUrl(url);
  }

  /// Creates a custom Gateway object from a URL for use with ArweaveService
  Gateway _createCustomGateway(String url) {
    final uri = Uri.parse(url);
    return Gateway(
      operatorStake: 0,
      gatewayAddress: 'custom',
      observerAddress: 'custom',
      settings: Settings(
        port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80),
        protocol: uri.scheme,
        allowDelegatedStaking: false,
        fqdn: uri.host,
        delegateRewardShareRatio: 0,
        properties: 'custom',
        note: 'Custom gateway',
        minDelegatedStake: 0,
        label: GatewayValidator.generateLabel(url),
        autoStake: false,
      ),
      startTimestamp: DateTime.now().millisecondsSinceEpoch,
      totalDelegatedStake: 0,
      stats: Stats(
        failedConsecutiveEpochs: 0,
        observedEpochCount: 0,
        passedConsecutiveEpochs: 0,
        totalEpochCount: 0,
        prescribedEpochCount: 0,
        passedEpochCount: 0,
        failedEpochCount: 0,
      ),
      status: 'custom',
    );
  }
}
