import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

const kMediumDialogWidth = 400.0;

class ManifestIdModal extends StatefulWidget {
  final Function(String) onSubmit;

  const ManifestIdModal({
    super.key,
    required this.onSubmit,
  });

  @override
  State<ManifestIdModal> createState() => _ManifestIdModalState();
}

class _ManifestIdModalState extends State<ManifestIdModal> {
  final _formKey = GlobalKey<FormState>();
  final _manifestIdController = TextEditingController();

  @override
  void dispose() {
    _manifestIdController.dispose();
    super.dispose();
  }

  String? _validateManifestId(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a manifest ID';
    }
    // Add additional validation if needed
    // Typically Arweave transaction IDs are 43 characters long and base64url encoded
    if (value.length != 43) {
      return 'Invalid manifest ID';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).addnewManifestEmphasized,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArDriveTextFieldNew(
                controller: _manifestIdController,
                validator: _validateManifestId,
                hintText: 'Enter manifest transaction ID',
                maxLines: 1,
                autofocus: true,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ArDriveButton(
                    text: appLocalizationsOf(context).cancel,
                    style: ArDriveButtonStyle.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  ArDriveButton(
                    text: 'Submit',
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSubmit(_manifestIdController.text);
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
