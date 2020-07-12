import 'package:flutter/material.dart';

Future<String> showTextFieldDialog(
  BuildContext context, {
  String title,
  String fieldLabel,
  String confirmingActionLabel,
  String initialText,
}) =>
    showDialog<String>(
      context: context,
      builder: (BuildContext context) => TextFieldDialog(
        title: title,
        fieldLabel: fieldLabel,
        confirmingActionLabel: confirmingActionLabel,
        initialText: initialText,
      ),
    );

class TextFieldDialog extends StatefulWidget {
  final String title;
  final String fieldLabel;
  final String confirmingActionLabel;
  final String initialText;

  const TextFieldDialog(
      {this.title,
      this.fieldLabel,
      this.confirmingActionLabel,
      this.initialText});

  @override
  TextFieldDialogState createState() => TextFieldDialogState();
}

class TextFieldDialogState extends State<TextFieldDialog> {
  TextEditingController fieldController;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    fieldController = TextEditingController(text: widget.initialText);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: TextFormField(
            autofocus: true,
            controller: fieldController,
            textCapitalization: TextCapitalization.words,
            validator: (value) =>
                value.isEmpty ? 'This field is required' : null,
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        actions: <Widget>[
          FlatButton(
            child: Text('CANCEL'),
            onPressed: () => Navigator.of(context).pop(null),
          ),
          FlatButton(
            child: Text(widget.confirmingActionLabel),
            onPressed: () {
              if (_formKey.currentState.validate())
                Navigator.of(context).pop(fieldController.text);
            },
          ),
        ],
      );
}
