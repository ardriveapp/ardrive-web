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
    return BlocConsumer<CreateUndernameBloc, CreateUndernameState>(
      listener: (context, state) {
        if (state is CreateUndernameSuccess) {
          setState(() {
            isLoading = false;
          });

          /// Refresh the AssignNameBloc to update the UI with the new undername in the dropdown list
          context.read<AssignNameBloc>().add(const LoadUndernames());
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        Widget content;
        List<ModalAction> actions = [];

        if (state is CreateUndernameFailure) {
          actions.add(ModalAction(
            action: () {
              Navigator.pop(context);
            },
            title: 'OK',
          ));
        } else {
          actions.add(ModalAction(
            action: () {
              Navigator.pop(context);
            },
            title: 'Cancel',
          ));
          actions.add(ModalAction(
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
          ));
        }

        final typography = ArDriveTypographyNew.of(context);

        if (state is CreateUndernameSuccess) {
          content = Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('Undername created successfully',
                style: typography.paragraphNormal()),
          );
        } else if (state is CreateUndernameFailure) {
          content = Text(
              'Undername already exists. Please choose a different name.',
              style: typography.paragraphNormal());
        } else if (state is CreateUndernameLoading) {
          content = Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('Creating undername...',
                style: typography.paragraphNormal()),
          );
        } else {
          content = CreateUndernameForm(onChanged: (text) {
            controller.text = text;
          });
        }

        return ArDriveStandardModalNew(
          width: kMediumDialogWidth,
          title: 'Create Undername',
          content: content,
          actions: actions,
        );
      },
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
