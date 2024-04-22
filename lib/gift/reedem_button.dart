import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/gift/bloc/redeem_gift_bloc.dart';
import 'package:ardrive/gift/redeem_gift_modal.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RedeemButton extends StatelessWidget {
  const RedeemButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveDropdown(
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
      ),
      items: [
        ArDriveDropdownItem(
          onClick: () {
            openUrl(url: Resources.sendGiftLink);
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).sendGift,
          ),
        ),
        ArDriveDropdownItem(
          onClick: () {
            showArDriveDialog(
              context,
              content: BlocProvider(
                create: (context) => RedeemGiftBloc(
                    paymentService: context.read<PaymentService>(),
                    auth: context.read<ArDriveAuth>()),
                child: const RedeemGiftModal(),
              ),
            );
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).redeemGift,
          ),
        ),
      ],
      child: ArDriveIconButton(
        icon: ArDriveIcons.gift(
          size: 20,
          color: colorTokens.textMid,
        ),
        tooltip: appLocalizationsOf(context).giftCredits,
      ),
    );
  }
}
