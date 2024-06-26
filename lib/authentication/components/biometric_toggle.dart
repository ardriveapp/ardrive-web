// ignore_for_file: use_build_context_synchronously

import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BiometricToggle extends StatefulWidget {
  const BiometricToggle({
    super.key,
    this.onDisableBiometric,
    this.onEnableBiometric,
    this.onError,
    this.padding,
  });

  final Function()? onEnableBiometric;
  final Function()? onDisableBiometric;
  final Function()? onError;
  final EdgeInsets? padding;

  @override
  State<BiometricToggle> createState() => _BiometricToggleState();
}

class _BiometricToggleState extends State<BiometricToggle> {
  @override
  void initState() {
    super.initState();
    _isBiometricsEnabled();
    _listenToBiometricChange();
  }

  bool _isEnabled = false;
  String get biometricText => _isEnabled
      ? appLocalizationsOf(context).biometricLoginEnabled
      : appLocalizationsOf(context).biometricLoginDisabled;

  Future<bool> _checkBiometricsSupport() async {
    final auth = context.read<BiometricAuthentication>();

    return auth.checkDeviceSupport();
  }

  Future<void> _isBiometricsEnabled() async {
    _isEnabled = await context.read<BiometricAuthentication>().isEnabled();

    setState(() {});
  }

  void _listenToBiometricChange() {
    context.read<BiometricAuthentication>().enabledStream.listen((event) {
      if (event != _isEnabled && mounted) {
        setState(() {
          _isEnabled = event;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
        future: _checkBiometricsSupport(),
        builder: (context, snapshot) {
          final hasSupport = snapshot.data;

          if (hasSupport == null || !hasSupport) {
            return const SizedBox();
          }

          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          final typography = ArDriveTypographyNew.of(context);

          return Padding(
            padding: widget.padding ?? const EdgeInsets.all(0),
            child: ArDriveToggleSwitch(
              text: biometricText,
              textStyle: typography.paragraphLarge(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold),
              value: _isEnabled,
              onChanged: (value) async {
                _isEnabled = value;

                if (_isEnabled) {
                  final auth = context.read<BiometricAuthentication>();

                  try {
                    if (await auth.authenticate(
                        localizedReason: appLocalizationsOf(context)
                            .loginUsingBiometricCredential)) {
                      setState(() {
                        _isEnabled = true;
                      });
                      context.read<BiometricAuthentication>().enable();
                      widget.onEnableBiometric?.call();
                      return;
                    }
                  } catch (e) {
                    widget.onError?.call();
                    if (e is BiometricException) {
                      showBiometricExceptionDialogForException(
                        context,
                        e,
                        () => widget.onDisableBiometric?.call(),
                      );
                    }
                  }
                } else {
                  context.read<BiometricAuthentication>().disable();

                  widget.onDisableBiometric?.call();
                }
                setState(() {
                  _isEnabled = false;
                });
              },
            ),
          );
        });
  }
}
