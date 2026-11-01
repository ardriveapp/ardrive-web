import 'package:ardrive/components/graphql_endpoint_dialog.dart';
import 'package:ardrive/components/turbo_url_dialog.dart';
import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/widgets/gateway_input_modal.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// The three servers a user can point the app at, and how to change or reset
// each. Used by the Settings page.

/// The GraphQL server in use: the stored one, or the app's fallback.
String graphQLServerOf(AppConfig config) =>
    config.arweaveGatewayUrl ?? defaultGraphqlGateway;

GarRepositoryImpl _garRepository(BuildContext context) => GarRepositoryImpl(
      configService: context.read<ConfigService>(),
      arweave: context.read<ArweaveService>(),
      arioSDK: ArioSDKFactory().create(),
      http: ArDriveHTTP(),
    );

/// Asks for a new gateway to read data from, and uses it once saved.
Future<void> showGatewayDialog(BuildContext context) {
  final garRepository = _garRepository(context);
  return showGatewayInputModal(
    context,
    initialGateway:
        context.read<ConfigService>().config.arweaveGatewayForDataRequest.url,
    onSave: garRepository.updateCustomGateway,
  );
}

/// Puts the gateway back to the one this build ships with.
Future<void> resetGateway(BuildContext context, AppConfig defaults) =>
    _garRepository(context)
        .updateCustomGateway(defaults.arweaveGatewayForDataRequest.url);

/// Asks for a new GraphQL server, and uses it once saved.
Future<void> showGraphQLServerDialog(BuildContext context) async {
  final configService = context.read<ConfigService>();
  final arweave = context.read<ArweaveService>();
  await showAnimatedDialogWithBuilder(
    context,
    builder: (context) => GraphQLEndpointDialog(
      initialEndpoint: graphQLServerOf(configService.config),
      onSave: (newEndpoint) => _useGraphQLServer(
        configService,
        arweave,
        newEndpoint,
      ),
    ),
  );
}

/// Puts the GraphQL server back to the one this build ships with.
Future<void> resetGraphQLServer(BuildContext context, AppConfig defaults) =>
    _useGraphQLServer(
      context.read<ConfigService>(),
      context.read<ArweaveService>(),
      graphQLServerOf(defaults),
    );

Future<void> _useGraphQLServer(
  ConfigService configService,
  ArweaveService arweave,
  String endpoint,
) async {
  const graphqlSuffix = '/graphql';
  final normalized = endpoint.endsWith(graphqlSuffix)
      ? endpoint.substring(0, endpoint.length - graphqlSuffix.length)
      : endpoint;
  await configService.updateAppConfig(
    configService.config.copyWith(arweaveGatewayUrl: normalized),
  );
  arweave.updateGraphQLEndpoint(normalized);
}

/// Asks for new Turbo upload and payment servers. The page reloads once they
/// are saved: Turbo's clients are built at start.
Future<void> showTurboServicesDialog(BuildContext context) async {
  final configService = context.read<ConfigService>();
  final config = configService.config;
  await showAnimatedDialogWithBuilder(
    context,
    builder: (context) => TurboUrlDialog(
      initialUploadUrl: config.defaultTurboUploadUrl ?? '',
      initialPaymentUrl: config.defaultTurboPaymentUrl ?? '',
      onSave: (uploadUrl, paymentUrl) async {
        await configService.updateAppConfig(
          config.copyWith(
            defaultTurboUploadUrl: uploadUrl,
            defaultTurboPaymentUrl: paymentUrl,
          ),
        );
        triggerHTMLPageReload();
      },
    ),
  );
}

/// Puts the Turbo servers back to the ones this build ships with, and reloads
/// the page as saving them does.
Future<void> resetTurboServices(
  BuildContext context,
  AppConfig defaults,
) async {
  final configService = context.read<ConfigService>();
  await configService.updateAppConfig(
    configService.config.copyWith(
      defaultTurboUploadUrl: defaults.defaultTurboUploadUrl,
      defaultTurboPaymentUrl: defaults.defaultTurboPaymentUrl,
    ),
  );
  triggerHTMLPageReload();
}
