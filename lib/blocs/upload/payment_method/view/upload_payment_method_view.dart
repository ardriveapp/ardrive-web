import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UploadPaymentMethodView extends StatelessWidget {
  const UploadPaymentMethodView({
    super.key,
    required this.onUploadMethodChanged,
    required this.onError,
    this.onTurboTopupSucess,
    this.loadingIndicator,
    this.useNewArDriveUI = false,
  });

  final Function(UploadMethod, UploadPaymentMethodInfo, bool)
      onUploadMethodChanged;
  final Function() onError;
  final Function()? onTurboTopupSucess;
  final Widget? loadingIndicator;
  final bool useNewArDriveUI;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UploadPaymentMethodBloc, UploadPaymentMethodState>(
      listener: (context, state) {
        if (state is UploadPaymentMethodLoaded) {
          logger.d(
              'UploadPaymentMethodLoaded: ${state.paymentMethodInfo.uploadMethod}');
          onUploadMethodChanged(
            state.paymentMethodInfo.uploadMethod,
            state.paymentMethodInfo,
            state.canUpload,
          );
        } else if (state is UploadPaymentMethodError) {
          onError();
        }
      },
      builder: (context, state) {
        if (state is UploadPaymentMethodLoaded) {
          return PaymentMethodSelector(
            useNewArDriveUI: useNewArDriveUI,
            uploadMethodInfo: state.paymentMethodInfo,
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
              onTurboTopupSucess?.call();
            },
          );
        }
        if (loadingIndicator != null) {
          return loadingIndicator!;
        }

        return const SizedBox.shrink();
      },
    );
  }
}
