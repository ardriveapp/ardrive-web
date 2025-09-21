import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UploadPaymentMethodView extends StatefulWidget {
  const UploadPaymentMethodView({
    super.key,
    required this.onUploadMethodChanged,
    required this.onError,
    this.onTurboTopupSucess,
    this.loadingIndicator,
    this.useNewArDriveUI = false,
    this.useDropdown = false,
  });

  final Function(UploadMethod, UploadPaymentMethodInfo, bool)
      onUploadMethodChanged;
  final Function() onError;
  final Function()? onTurboTopupSucess;
  final Widget? loadingIndicator;
  final bool useNewArDriveUI;
  final bool useDropdown;

  @override
  State<UploadPaymentMethodView> createState() => _UploadPaymentMethodViewState();
}

class _UploadPaymentMethodViewState extends State<UploadPaymentMethodView> {
  bool _showCongestionWarning = false;
  
  // Debug flag - set to true to test congestion warning
  static const bool _debugForceCongestionWarning = false;

  @override
  void initState() {
    super.initState();
    _checkCongestion();
  }

  Future<void> _checkCongestion() async {
    // Debug mode - force show warning for testing
    if (_debugForceCongestionWarning) {
      if (mounted) {
        setState(() {
          _showCongestionWarning = true;
        });
      }
      return;
    }
    
    try {
      final mempoolSize = await context.read<ArweaveService>().getMempoolSizeFromArweave();
      if (mounted) {
        setState(() {
          _showCongestionWarning = mempoolSize > mempoolWarningSizeLimit;
        });
      }
    } catch (e) {
      logger.d('Failed to check mempool congestion: $e');
      if (mounted) {
        setState(() {
          _showCongestionWarning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UploadPaymentMethodBloc, UploadPaymentMethodState>(
      listener: (context, state) {
        if (state is UploadPaymentMethodLoaded) {
          logger.d(
              'UploadPaymentMethodLoaded: ${state.paymentMethodInfo.uploadMethod}');
          widget.onUploadMethodChanged(
            state.paymentMethodInfo.uploadMethod,
            state.paymentMethodInfo,
            state.canUpload,
          );
        } else if (state is UploadPaymentMethodError) {
          widget.onError();
        }
      },
      builder: (context, state) {
        if (state is UploadPaymentMethodLoaded) {
          return PaymentMethodSelector(
            useNewArDriveUI: widget.useNewArDriveUI,
            uploadMethodInfo: state.paymentMethodInfo,
            useDropdown: widget.useDropdown,
            showCongestionWarning: _showCongestionWarning,
            onArSelect: () {
              context.read<UploadPaymentMethodBloc>().add(
                    const ChangeUploadPaymentMethod(
                      paymentMethod: UploadMethod.ar,
                    ),
                  );
            },
            onTurboSelect: () {
              context.read<UploadPaymentMethodBloc>().add(
                    const ChangeUploadPaymentMethod(
                      paymentMethod: UploadMethod.turbo,
                    ),
                  );
            },
            onTurboTopupSucess: () {
              widget.onTurboTopupSucess?.call();
            },
          );
        }
        if (widget.loadingIndicator != null) {
          return widget.loadingIndicator!;
        }

        return const SizedBox.shrink();
      },
    );
  }
}
