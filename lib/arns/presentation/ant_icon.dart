import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/tooltip.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AntIcon extends StatefulWidget {
  const AntIcon({super.key, required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  State<AntIcon> createState() => _AntIconState();
}

final sdk = ArioSDKFactory().create();

class _AntIconState extends State<AntIcon> {
  bool? stillAvailable;
  ARNSUndername? undername;

  @override
  void initState() {
    super.initState();

    checkAvailability();
  }

  Future<void> checkAvailability() async {
    final arnsRepository = ARNSRepository(
      sdk: sdk,
      auth: context.read<ArDriveAuth>(),
      fileRepository: context.read<FileRepository>(),
      arnsDao: ARNSDao(context.read<Database>()),
    );
    final stillAvailableResult =
        await arnsRepository.nameIsStillAvailableToFile(
            widget.fileDataTableItem.fileId, widget.fileDataTableItem.driveId);

    stillAvailable = stillAvailableResult.$1;
    undername = stillAvailableResult.$2;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (stillAvailable == null) {
      return const SizedBox();
    }

    if (stillAvailable!) {
      final typography = ArDriveTypographyNew.of(context);
      final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
      return GestureDetector(
        onTap: () {
          String address = '';

          if (undername != null) {
            if (undername!.name == '@') {
              address = undername!.domain;
            } else {
              address = '${undername!.name}_${undername!.domain}';
            }
          }

          address = '$address.ar-io.dev';

          openUrl(
            url: 'https://$address',
          );
        },
        child: ArDriveTooltip(
          message: '${undername?.name ?? '@'}_${undername?.domain}.ar-io.dev',
          child: ArDriveClickArea(
            child: ArDriveIcons.arnsName(
              size: 18,
              color: const Color(0xffFFBB38),
            ),
          ),
        ),
      );
    } else {
      return const SizedBox();
    }
  }
}
