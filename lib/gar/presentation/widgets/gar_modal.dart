import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_http/ardrive_http.dart';
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
        garRepository: GarRepositoryImpl(
          configService: context.read<ConfigService>(),
          arweave: context.read<ArweaveService>(),
          arioSDK: ArioSDKFactory().create(),
          http: ArDriveHTTP(),
        ),
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
  final TextEditingController _searchController = TextEditingController();

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GarBloc, GarState>(
      builder: (context, state) {
        if (state is GatewayActive) {
          return _ConfirmGatewayChange(
            gateway: state.gateway,
            garBloc: context.read<GarBloc>(),
            searchQuery: _searchController.text,
          );
        }

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
                  SearchTextField(
                    labelText: 'Search gateway',
                    hintText: 'Search for a gateway',
                    onChanged: (value) {
                      if (value.isEmpty) {
                        garBloc.add(CleanSearchResults());
                        return;
                      }

                      garBloc.add(SearchGateways(query: value));
                    },
                    controller: _searchController,
                    onFieldSubmitted: (value) {
                      garBloc.add(SearchGateways(query: value));
                    },
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
                                    : ArFontWeight.semiBold,
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
                              context
                                  .read<GarBloc>()
                                  .add(SelectGateway(gateway: gateway));
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

        if (state is VerifyingGateway) {
          return const ProgressDialog(
            title: 'Verifying if gateway is active',
            useNewArDriveUI: true,
          );
        }

        if (state is GatewayChanged) {
          final typography = ArDriveTypographyNew.of(context);
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          return ArDriveStandardModalNew(
            title: 'Gateway Changed',
            content: Column(
              children: [
                RichText(
                  text: TextSpan(
                    style:
                        typography.paragraphLarge(color: colorTokens.textMid),
                    children: [
                      const TextSpan(
                          text:
                              'You have successfully changed the gateway to '),
                      TextSpan(
                        text: state.gateway.settings.label,
                        style: typography.paragraphLarge(
                          color: colorTokens.textHigh,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                      TextSpan(
                          text: '!',
                          style: typography.paragraphLarge(
                              color: colorTokens.textMid)),
                    ],
                  ),
                ),
              ],
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

        if (state is GatewayIsInactive) {
          return ArDriveStandardModalNew(
            title: 'Inactive Gateway',
            description:
                'The selected gateway is inactive. Please select a different gateway.',
            actions: [
              ModalAction(
                action: () {
                  final garBloc = context.read<GarBloc>();
                  garBloc.add(GetGateways());

                  if (_searchController.text.isNotEmpty) {
                    garBloc.add(SearchGateways(query: _searchController.text));
                  }
                },
                title: 'OK',
              ),
            ],
          );
        }

        if (state is GatewaysError) {
          return ArDriveStandardModalNew(
            hasCloseButton: true,
            title: 'Error',
            description:
                'An error occurred while loading the gateways. Please try again.',
            actions: [
              ModalAction(
                action: () {
                  Navigator.of(context).pop();
                },
                title: 'Close',
              ),
              ModalAction(
                action: () {
                  context.read<GarBloc>().add(GetGateways());
                },
                title: 'Try again',
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
  const _ConfirmGatewayChange({
    required this.gateway,
    required this.garBloc,
    this.searchQuery,
  });

  final Gateway gateway;
  final GarBloc garBloc;
  final String? searchQuery;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      title: 'Switch Gateway',
      content: Column(
        children: [
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: <TextSpan>[
                TextSpan(
                  text: 'Are you sure you want to change the gateway to: ',
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.book,
                  ),
                ),
                TextSpan(
                  text: gateway.settings.label,
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '?',
                  style: typography.paragraphLarge(
                    fontWeight: ArFontWeight.book,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      actions: [
        ModalAction(
          action: () {
            garBloc.add(GetGateways());

            if (searchQuery != null && searchQuery!.isNotEmpty) {
              garBloc.add(SearchGateways(query: searchQuery!));
            }
          },
          title: 'No',
        ),
        ModalAction(
          action: () {
            garBloc.add(
              ConfirmGatewayChange(gateway: gateway),
            );
          },
          title: 'Yes',
        ),
      ],
    );
  }
}
