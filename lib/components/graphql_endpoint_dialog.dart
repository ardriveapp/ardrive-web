import 'dart:async';
import 'dart:convert';

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GraphQLEndpointDialog extends StatefulWidget {
  final String initialEndpoint;
  final Function(String) onSave;

  const GraphQLEndpointDialog({
    super.key,
    required this.initialEndpoint,
    required this.onSave,
  });

  @override
  State<GraphQLEndpointDialog> createState() => _GraphQLEndpointDialogState();
}

class _GraphQLEndpointDialogState extends State<GraphQLEndpointDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _endpointController;
  bool _isLoading = false;
  bool? _isValid;

  /// Set before the save runs: a second press must not save (and close) twice.
  bool _saving = false;
  Timer? _debounce;
  String _lastValidatedText = '';

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: widget.initialEndpoint);
    _lastValidatedText = widget.initialEndpoint;
    _endpointController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _endpointController.removeListener(_onTextChanged);
    _endpointController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final currentText = _endpointController.text.trim();
    if (currentText != _lastValidatedText) {
      _validateEndpoint();
    }
  }

  Future<void> _validateEndpoint() async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final endpoint = _endpointController.text.trim();

      if (endpoint == _lastValidatedText) return;

      _lastValidatedText =
          endpoint; // Update last validated text before starting validation

      if (endpoint.isEmpty) {
        setState(() {
          _isValid = false;
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = true);

      try {
        final isValid = await _isValidGraphQLEndpoint(endpoint);

        if (mounted) {
          setState(() {
            _isValid = isValid;
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _isValid = false;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return ArDriveStandardModalNew(
      width: 500,
      title: strings.graphqlServerTitle,
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArDriveTextFieldNew(
                controller: _endpointController,
                hintText: strings.graphqlServerUrlHint,
                label: strings.graphqlServerUrlLabel,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return strings.urlRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: ArDriveSpacing.xs),
              _isLoading
                  ? Row(
                      children: [
                        const ArDriveSpinner(),
                        const SizedBox(width: ArDriveSpacing.xs),
                        Text(
                          strings.graphqlServerChecking,
                          style:
                              ArDriveTypographyNew.of(context).paragraphSmall(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colorTokens
                                .textMid,
                          ),
                        ),
                      ],
                    )
                  : _endpointController.text.isNotEmpty && _isValid == false
                      ? ArDriveNotice(
                          type: ArDriveNoticeType.error,
                          message: strings.graphqlServerInvalid,
                        )
                      : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      actions: [
        ModalAction.close(
          title: strings.cancel,
          action: () => Navigator.of(context).pop(),
        ),
        ModalAction(
          title: strings.save,
          isEnable: _isValid == true && !_isLoading && !_saving,
          action: () {
            if (_saving) return;
            if (_formKey.currentState!.validate()) {
              _saving = true;
              widget.onSave(_endpointController.text.trim());
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  Future<bool> _isValidGraphQLEndpoint(String endpoint) async {
    const query = '''
      query {
        __typename
      }
    ''';

    final response = await http
        .post(
          Uri.parse('$endpoint/graphql'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query}),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['data'] != null &&
          jsonResponse['data']['__typename'] == 'Query';
    }
    return false;
  }
}
