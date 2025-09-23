import 'package:ardrive/components/graphql_endpoint_dialog.dart';
import 'package:ardrive/gar/presentation/widgets/gar_modal.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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
            showGatewaySwitcherModal(context);
          },
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            child: ArDriveDropdownItemTile(
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
            child: ArDriveDropdownItemTile(
              name: 'Set GraphQL Server',
            ),
          ),
        ),
      ],
      child: child,
    );
  }

  void _showGraphQLEndpointDialog(BuildContext context) {
    final configService = context.read<ConfigService>();
    final currentEndpoint =
        configService.config.defaultArweaveGatewayUrl ?? 'https://arweave.net';

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
              defaultArweaveGatewayUrl: normalizedEndpoint,
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
