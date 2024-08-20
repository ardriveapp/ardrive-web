import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GatewaySwitcherModal extends StatelessWidget {
  const GatewaySwitcherModal({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => GarBloc(
        configService: context.read<ConfigService>(),
        arweave: context.read<ArweaveService>(),
        arioSDK: ArioSDKFactory().create(),
      )..add(GetGateways()),
      child: _GatewaySwitcherModal(),
    );
  }
}

class _GatewaySwitcherModal extends StatefulWidget {
  @override
  State<_GatewaySwitcherModal> createState() => _GatewaySwitcherModalState();
}

class _GatewaySwitcherModalState extends State<_GatewaySwitcherModal> {
  final TextEditingController _arweaveGatewayUrlController =
      TextEditingController();

  @override
  initState() {
    super.initState();

    _arweaveGatewayUrlController.text = context
        .read<ConfigService>()
        .config
        .defaultArweaveGatewayForDataRequest
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GarBloc, GarState>(
      builder: (context, state) {
        if (state is GatewaysLoaded) {
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          final typography = ArDriveTypographyNew.of(context);
          final garBloc = context.read<GarBloc>();
          return ArDriveStandardModalNew(
            width: 500,
            title: 'Select Gateway',
            content: SizedBox(
              height: 500,
              width: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.currentGateway != null) ...[
                    Text(
                      'Current gateway: ${state.currentGateway!.settings.label}',
                      style: typography.heading6(
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16)
                  ],
                  ArDriveTextFieldNew(
                    label: 'Search gateway',
                    hintText: 'Search for a gateway',
                    onChanged: (value) {
                      if (value.isEmpty) {
                        garBloc.add(CleanSearchResults());
                        return;
                      }

                      garBloc.add(SearchGateways(query: value));
                    },
                    suffixIcon: GestureDetector(
                      child: ArDriveIcons.closeRectangle(),
                      onTap: () {
                        garBloc.add(CleanSearchResults());
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      separatorBuilder: (context, index) => const SizedBox(
                        height: 4,
                      ),
                      shrinkWrap: true,
                      itemCount: state.searchResults != null
                          ? state.searchResults!.length
                          : state.gateways.length,
                      itemBuilder: (context, index) {
                        final gateway = state.searchResults != null
                            ? state.searchResults![index]
                            : state.gateways[index];

                        return ArDriveCard(
                          backgroundColor: gateway == state.currentGateway
                              ? colorTokens.containerL0
                              : colorTokens.containerL1,
                          content: ListTile(
                            title: Text(
                              gateway.settings.label,
                              style: typography.paragraphLarge(
                                color: state.currentGateway == gateway
                                    ? colorTokens.textHigh
                                    : colorTokens.textMid,
                                fontWeight: state.currentGateway == gateway
                                    ? ArFontWeight.bold
                                    : ArFontWeight.book,
                              ),
                            ),
                            subtitle: Text(
                              gateway.settings.fqdn,
                              style: typography.paragraphSmall(
                                color: state.currentGateway == gateway
                                    ? colorTokens.textHigh
                                    : colorTokens.textMid,
                                fontWeight: state.currentGateway == gateway
                                    ? ArFontWeight.bold
                                    : ArFontWeight.book,
                              ),
                            ),
                            trailing: ArDriveIcons.carretRight(),
                            onTap: () {
                              showArDriveDialog(
                                context,
                                content: _ConfirmGatewayChange(
                                  gateway: gateway,
                                  garBloc: garBloc,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ModalAction(
                action: () {
                  Navigator.of(context).pop();
                },
                title: 'Close',
              ),
            ],
          );
        }

        if (state is GatewayChanged) {
          return ArDriveStandardModalNew(
            title: 'Gateway Switcher',
            description:
                'You have successfully changed the gateway to ${state.gateway.settings.fqdn}!!!',
            actions: [
              ModalAction(
                action: () {
                  Navigator.of(context).pop();
                },
                title: 'Close',
              ),
            ],
          );
        }

        return ProgressDialog(
          title: 'Loading Gateways',
          useNewArDriveUI: true,
          actions: [
            ModalAction(
              action: () {
                Navigator.of(context).pop();
              },
              title: 'Cancel',
            ),
          ],
        );
      },
    );
  }
}

Future<void> showGatewaySwitcherModal(BuildContext context) {
  return showArDriveDialog(
    context,
    content: const GatewaySwitcherModal(),
  );
}

class _ConfirmGatewayChange extends StatelessWidget {
  const _ConfirmGatewayChange({required this.gateway, required this.garBloc});

  final Gateway gateway;
  final GarBloc garBloc;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: 'Switch Gateway',
      description:
          'Are you sure you want to change the gateway to ${gateway.settings.label}?',
      actions: [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: 'No',
        ),
        ModalAction(
          action: () {
            garBloc.add(
              UpdateArweaveGatewayUrl(
                gateway: gateway,
              ),
            );

            Navigator.of(context).pop();
          },
          title: 'Yes',
        ),
      ],
    );
  }
}
