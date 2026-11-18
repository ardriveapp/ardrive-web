import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The ar.io gateways to choose from, shown inside the dialog that asks for
/// one (the gateway dialog), not in a second dialog on top of it. The dialog
/// owns the title and the Back action; this is the search field and the rows.
class ArIOGatewayPicker extends StatelessWidget {
  const ArIOGatewayPicker({
    super.key,
    required this.onSelected,
    this.createBloc,
  });

  final void Function(Gateway gateway) onSelected;

  /// Builds the bloc. Replaced in tests.
  final GarBloc Function(BuildContext context)? createBloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => (createBloc?.call(context) ??
          GarBloc(
            garRepository: GarRepositoryImpl(
              configService: context.read<ConfigService>(),
              arweave: context.read<ArweaveService>(),
              arioSDK: ArioSDKFactory().create(),
              http: ArDriveHTTP(),
            ),
          ))
        ..add(GetGateways()),
      child: _GatewayList(onSelected: onSelected),
    );
  }
}

class _GatewayList extends StatefulWidget {
  const _GatewayList({required this.onSelected});

  final void Function(Gateway gateway) onSelected;

  @override
  State<_GatewayList> createState() => _GatewayListState();
}

class _GatewayListState extends State<_GatewayList> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return BlocBuilder<GarBloc, GarState>(
      builder: (context, state) {
        if (state is GatewaysError) {
          return ArDriveNotice(
            type: ArDriveNoticeType.error,
            title: strings.gatewayLoadFailedTitle,
            message: strings.gatewayLoadFailedBody,
            actionLabel: strings.tryAgain,
            onAction: () => context.read<GarBloc>().add(GetGateways()),
          );
        }

        if (state is! GatewaysLoaded) {
          return const SizedBox(
            height: 240,
            child: Center(
              child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
            ),
          );
        }

        final garBloc = context.read<GarBloc>();
        final gateways = state.searchResults ?? state.gateways;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchTextField(
              labelText: strings.gatewaySearch,
              hintText: strings.gatewaySearch,
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
            const SizedBox(height: ArDriveSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: gateways.length,
                itemBuilder: (context, index) {
                  final gateway = gateways[index];
                  return ArDriveChoiceItem(
                    key: ValueKey('gateway-${gateway.settings.fqdn}'),
                    label:
                        '${gateway.settings.label} (${gateway.settings.fqdn})',
                    selected: gateway == state.currentGateway,
                    onPressed: () => widget.onSelected(gateway),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
