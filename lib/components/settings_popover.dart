import 'package:ardrive/components/graphql_endpoint_dialog.dart';
import 'package:ardrive/components/turbo_url_dialog.dart';
import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/widgets/gateway_input_modal.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsSubmenu extends StatelessWidget {
  final Widget child;

  const SettingsSubmenu({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveSubmenu(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        ArDriveSubmenuItem(
          onClick: () {
            _showGatewayInputDialog(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: const ArDriveDropdownItemTile(
              name: 'Set Gateway',
            ),
          ),
        ),
        ArDriveSubmenuItem(
          onClick: () {
            _showGraphQLEndpointDialog(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: const ArDriveDropdownItemTile(
              name: 'Set GraphQL Server',
            ),
          ),
        ),
        ArDriveSubmenuItem(
          onClick: () {
            _showTurboUrlDialog(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: const ArDriveDropdownItemTile(
              name: 'Set Turbo Services',
            ),
          ),
        ),
        ArDriveSubmenuItem(
          widget: StreamBuilder<UserPreferences>(
            stream: context.read<UserPreferencesRepository>().watch(),
            builder: (context, streamSnapshot) {
              final repo = context.read<UserPreferencesRepository>();
              final syncAllDrivesOnLogin =
                  streamSnapshot.data?.syncAllDrivesOnLogin ??
                      repo.currentPreferences?.syncAllDrivesOnLogin ??
                      true;
              return ArDriveHoverWidget(
                hoverColor: ArDriveTheme.of(context)
                    .themeData
                    .dropdownTheme
                    .hoverColor,
                defaultColor: ArDriveTheme.of(context)
                    .themeData
                    .dropdownTheme
                    .backgroundColor,
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18.0),
                    child: ArDriveToggleSwitch(
                      value: syncAllDrivesOnLogin,
                      text: appLocalizationsOf(context).syncAllDrivesOnLogin,
                      textStyle: ArDriveTypography.body.buttonNormalBold(),
                      onChanged: (value) {
                        repo.saveSyncAllDrivesOnLogin(value);
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
      child: child,
    );
  }

  void _showGatewayInputDialog(BuildContext context) {
    final configService = context.read<ConfigService>();
    final currentGateway = configService.config.arweaveGatewayForDataRequest.url;

    showGatewayInputModal(
      context,
      initialGateway: currentGateway,
      onSave: (newGatewayUrl) async {
        // Create a repository instance to handle the gateway update
        final garRepository = GarRepositoryImpl(
          configService: configService,
          arweave: context.read<ArweaveService>(),
          arioSDK: ArioSDKFactory().create(),
          http: ArDriveHTTP(),
        );

        // Use the repository to update the custom gateway
        await garRepository.updateCustomGateway(newGatewayUrl);
      },
    );
  }

  void _showTurboUrlDialog(BuildContext context) {
    final configService = context.read<ConfigService>();
    final config = configService.config;

    showArDriveDialog(
      context,
      content: TurboUrlDialog(
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

  void _showGraphQLEndpointDialog(BuildContext context) {
    final configService = context.read<ConfigService>();
    final currentEndpoint =
        configService.config.arweaveGatewayUrl ?? defaultGraphqlGateway;

    showArDriveDialog(
      context,
      content: GraphQLEndpointDialog(
        initialEndpoint: currentEndpoint,
        onSave: (newEndpoint) {
          const graphqlSuffix = '/graphql';
          final normalizedEndpoint = newEndpoint.endsWith(graphqlSuffix)
              ? newEndpoint.substring(
                  0, newEndpoint.length - graphqlSuffix.length)
              : newEndpoint;

          configService.updateAppConfig(
            configService.config.copyWith(
              arweaveGatewayUrl: normalizedEndpoint,
            ),
          );

          context
              .read<ArweaveService>()
              .updateGraphQLEndpoint(normalizedEndpoint);
        },
      ),
    );
  }
}
