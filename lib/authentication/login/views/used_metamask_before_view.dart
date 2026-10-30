import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

/// Asked when no record of this MetaMask's ArDrive account was found
/// anywhere: a new account, or one made before 3.0 whose record no index
/// has. Only the person knows which.
class UsedMetaMaskBeforeView extends StatelessWidget {
  const UsedMetaMaskBeforeView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final bloc = context.read<LoginBloc>();

    return SizedBox(
      width: 381,
      child: LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Center(
                child: SvgPicture.asset(
                  Resources.images.login.metamask,
                  width: 64,
                  height: 64,
                ),
              ),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              s.usedMetaMaskBeforeTitle,
              textAlign: TextAlign.center,
              style: type.heading2(
                color: colors.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            ArDriveButtonNew(
              key: const Key('usedMetaMaskBeforeNo'),
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              typography: type,
              text: s.usedMetaMaskBeforeNo,
              variant: ButtonVariant.primary,
              onPressed: () =>
                  bloc.add(const AnswerUsedArDriveBefore(usedBefore: false)),
            ),
            const SizedBox(height: ArDriveSpacing.sm),
            ArDriveButtonNew(
              key: const Key('usedMetaMaskBeforeYes'),
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              typography: type,
              text: s.usedMetaMaskBeforeYes,
              variant: ButtonVariant.secondary,
              onPressed: () =>
                  bloc.add(const AnswerUsedArDriveBefore(usedBefore: true)),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            Center(
              child: ArDriveLink(
                key: const Key('usedMetaMaskBeforeBack'),
                text: s.back,
                isAction: true,
                onTap: () => bloc.add(const LeaveWallet(toLogIn: true)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
