import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UploadPaymentMethodView extends StatelessWidget {
  const UploadPaymentMethodView({
    super.key,
    required this.params,
    required this.onUploadMethodChanged,
    this.onTurboTopupSucess,
  });

  final Function(UploadMethod) onUploadMethodChanged;
  final Function? onTurboTopupSucess;

  final UploadParams params;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => UploadPaymentMethodBloc(
          context.read<ProfileCubit>(),
          context.read<ArDriveUploadPreparationManager>(),
          context.read<ArDriveAuth>())
        ..add(PrepareUploadPaymentMethod(params: params)),
      child: Builder(builder: (context) {
        return BlocBuilder<UploadPaymentMethodBloc, UploadPaymentMethodState>(
            builder: (context, state) {
          if (state is UploadPaymentMethodLoaded) {
            return PaymentMethodSelector(
              uploadMethodInfo: state.paymentMethodInfo,
              onArSelect: () {
                context
                    .read<UploadPaymentMethodBloc>()
                    .add(const ChangeUploadPaymentMethod(
                      paymentMethod: UploadMethod.ar,
                    ));
                onUploadMethodChanged(UploadMethod.ar);
              },
              onTurboSelect: () {
                context
                    .read<UploadPaymentMethodBloc>()
                    .add(const ChangeUploadPaymentMethod(
                      paymentMethod: UploadMethod.turbo,
                    ));
                onUploadMethodChanged(UploadMethod.turbo);
              },
              onTurboTopupSucess: () {
                onTurboTopupSucess?.call();
              },
            );
          }

          return const Center(child: CircularProgressIndicator());
        });
      }),
    );
  }
}
