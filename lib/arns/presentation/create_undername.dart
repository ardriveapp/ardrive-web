import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/presentation/assign_name_bloc/assign_name_bloc.dart';
import 'package:ardrive/arns/presentation/create_undername/create_undername_bloc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CreateUndernameModal extends StatelessWidget {
  const CreateUndernameModal({
    super.key,
    required this.nameModel,
    required this.driveId,
    required this.fileId,
    required this.transactionId,
  });

  final ArNSNameModel nameModel;
  final String driveId;
  final String fileId;
  final String transactionId;
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CreateUndernameBloc(
        context.read<ARNSRepository>(),
        nameModel,
        driveId,
        fileId,
        transactionId,
      ),
      child: const CreateUndernameView(),
    );
  }
}

class CreateUndernameView extends StatefulWidget {
  const CreateUndernameView({super.key});

  @override
  State<CreateUndernameView> createState() => _CreateUndernameViewState();
}

class _CreateUndernameViewState extends State<CreateUndernameView> {
  final controller = TextEditingController();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: 'Create Undername',
      content: BlocConsumer<CreateUndernameBloc, CreateUndernameState>(
        listener: (context, state) {
          if (state is CreateUndernameSuccess) {
            setState(() {
              isLoading = false;
            });
            context.read<AssignNameBloc>().add(
                  ShowSuccessModal(
                    undername: state.undername,
                  ),
                );
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          final typography = ArDriveTypographyNew.of(context);
          if (state is CreateUndernameSuccess) {
            return Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('Undername created successfully',
                  style: typography.paragraphNormal()),
            );
          }

          if (state is CreateUndernameLoading) {
            return Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('Creating undername...',
                  style: typography.paragraphNormal()),
            );
          }

          return CreateUndernameForm(onChanged: (text) {
            controller.text = text;
          });
        },
      ),
      actions: [
        ModalAction(
          action: () {
            Navigator.pop(context);
          },
          title: 'Cancel',
        ),
        ModalAction(
          isEnable: controller.text.isNotEmpty && !isLoading,
          action: () {
            setState(() {
              isLoading = true;
            });
            context
                .read<CreateUndernameBloc>()
                .add(CreateNewUndername(controller.text));
          },
          title: 'Create',
        ),
      ],
    );
  }
}

class CreateUndernameForm extends StatelessWidget {
  const CreateUndernameForm({super.key, required this.onChanged});

  final Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return ArDriveTextFieldNew(
      label: 'Undername',
      hintText: 'Enter your undername',
      onChanged: onChanged,
    );
  }
}
