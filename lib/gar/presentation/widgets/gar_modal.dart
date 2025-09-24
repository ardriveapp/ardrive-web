import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<Gateway?> showArIOGatewaySelectorModal(BuildContext context) async {
  return await showAnimatedDialogWithBuilder<Gateway>(
    context,
    builder: (context) => const ArIOGatewaySelectorModal(),
  );
}

class ArIOGatewaySelectorModal extends StatelessWidget {
  const ArIOGatewaySelectorModal({super.key});

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
      child: _ArIOGatewaySelectorModalContent(),
    );
  }
}

class _ArIOGatewaySelectorModalContent extends StatefulWidget {
  @override
  State<_ArIOGatewaySelectorModalContent> createState() => _ArIOGatewaySelectorModalContentState();
}

class _ArIOGatewaySelectorModalContentState extends State<_ArIOGatewaySelectorModalContent> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GarBloc, GarState>(
      listener: (context, state) {
        // Handle side effects here if needed
      },
      builder: (context, state) {
        if (state is GatewaysLoaded) {
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          final typography = ArDriveTypographyNew.of(context);
          final garBloc = context.read<GarBloc>();
          
          return ArDriveStandardModalNew(
            width: 500,
            title: 'Select AR.IO Gateway',
            content: SizedBox(
              height: 400,
              width: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      separatorBuilder: (context, index) => const SizedBox(height: 4),
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
                              Navigator.of(context).pop(gateway);
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
                title: 'Cancel',
              ),
            ],
          );
        }

        if (state is GatewaysError) {
          return ArDriveStandardModalNew(
            hasCloseButton: true,
            title: 'Error',
            description: 'An error occurred while loading the gateways. Please try again.',
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
