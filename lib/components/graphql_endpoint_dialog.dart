import 'dart:async';
import 'dart:convert';

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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      width: 500,
      title: 'Switch GraphQL Server',
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the URL of the GraphQL server you want to use',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              const SizedBox(height: 16),
              ArDriveTextFieldNew(
                controller: _endpointController,
                hintText: 'Enter host name (e.g. https://ardrive.net)',
                label: 'GraphQL Server URL',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              _isLoading
                  ? Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorTokens.buttonPrimaryDefault,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Validating endpoint...',
                          style: typography.paragraphSmall(
                            color: colorTokens.textMid,
                          ),
                        ),
                      ],
                    )
                  : _endpointController.text.isNotEmpty && _isValid == false
                      ? Row(
                          children: [
                            Icon(
                              Icons.error,
                              size: 16,
                              color: colorTokens.buttonPrimaryPress,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Invalid GraphQL endpoint',
                              style: typography.paragraphSmall(
                                color: colorTokens.buttonPrimaryPress,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      actions: [
        ModalAction(
          title: 'Cancel',
          action: () => Navigator.of(context).pop(),
        ),
        ModalAction(
          title: 'Save',
          isEnable: _isValid == true && !_isLoading,
          action: () {
            if (_formKey.currentState!.validate()) {
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
