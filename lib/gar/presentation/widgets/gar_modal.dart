import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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
      ),
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
        .defaultArweaveGatewayUrl
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GarBloc, GarState>(
      builder: (context, state) {
        if (state is GatewayChanged) {
          return ArDriveStandardModalNew(
            title: 'Gateway Switcher',
            description:
                'You have successfully changed the gateway URL to ${_arweaveGatewayUrlController.text}!!!',
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

        return ArDriveStandardModalNew(
          title: 'Gateway Switcher',
          content: _form(),
          actions: [
            ModalAction(
                action: () {
                  try {
                    context.read<GarBloc>().add(
                          UpdateArweaveGatewayUrl(
                            arweaveGatewayUrl:
                                _arweaveGatewayUrlController.text,
                          ),
                        );
                  } catch (e) {
                    return;
                  }
                },
                title: 'Save')
          ],
        );
      },
    );
  }

  Widget _form() {
    return Column(
      children: [
        ArDriveTextFieldNew(
          controller: _arweaveGatewayUrlController,
          label: 'Arweave Gateway URL',
          onChanged: (value) {},
        ),
      ],
    );
  }
}

Future<void> showGatewaySwitcherModal(BuildContext context) {
  return showArDriveDialog(
    context,
    content: const GatewaySwitcherModal(),
  );
}
