import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';

/// One line above the explorer for somebody viewing a drive without signing
/// in, with the one thing they might want to do about it.
///
/// Shown only while there is no profile. Dismissing it lasts for the session;
/// a reload brings it back, which is right for a strip whose job is to be
/// seen once per visit rather than remembered.
class VisitorBanner extends StatefulWidget {
  const VisitorBanner({super.key});

  /// Session-wide, so moving between drives does not bring it back.
  static bool dismissedThisSession = false;

  @override
  State<VisitorBanner> createState() => _VisitorBannerState();
}

class _VisitorBannerState extends State<VisitorBanner> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is ProfileLoggedIn || VisitorBanner.dismissedThisSession) {
          return const SizedBox.shrink();
        }

        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
        final typography = ArDriveTypographyNew.of(context);
        final strings = appLocalizationsOf(context);
        final narrow = MediaQuery.of(context).size.width < TABLET;

        final message = Text(
          strings.visitorBannerMessage,
          style: typography.paragraphNormal(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.semiBold,
          ),
        );

        final signIn = ArDriveButtonNew(
          key: const Key('visitorBannerSignIn'),
          text: strings.visitorBannerSignIn,
          typography: typography,
          variant: ButtonVariant.primary,
          maxHeight: 36,
          maxWidth: 120,
          onPressed: () =>
              context.read<AppRouterDelegate>().signInKeepingDrive(),
        );

        final dismiss = ArDriveClickArea(
          tooltip: strings.close,
          child: GestureDetector(
            key: const Key('visitorBannerDismiss'),
            onTap: () => setState(() {
              VisitorBanner.dismissedThisSession = true;
            }),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ArDriveIcons.x(size: 16, color: colorTokens.textLow),
            ),
          ),
        );

        return Container(
          key: const Key('visitorBanner'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: colorTokens.containerL2,
            border: Border(
              bottom: BorderSide(color: colorTokens.strokeLow),
            ),
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: message),
                        dismiss,
                      ],
                    ),
                    const SizedBox(height: 8),
                    signIn,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: message),
                    const SizedBox(width: 16),
                    signIn,
                    const SizedBox(width: 8),
                    dismiss,
                  ],
                ),
        );
      },
    );
  }
}
