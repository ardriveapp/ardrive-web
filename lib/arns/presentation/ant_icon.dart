import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AntIcon extends StatefulWidget {
  const AntIcon({super.key, required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  State<AntIcon> createState() => _AntIconState();
}

final sdk = ArioSDKFactory().create();

class _AntIconState extends State<AntIcon> {
  ArnsRecord? undername;
  bool? stillAvailable;

  @override
  void initState() {
    super.initState();

    _checkIfStillAvailable();
  }

  Future<void> _checkIfStillAvailable() async {
    final arnsRepository = context.read<ARNSRepository>();

    final activeARNSRecords = await arnsRepository
        .getActiveARNSRecordsForFile(widget.fileDataTableItem.fileId);

    if (activeARNSRecords.isNotEmpty) {
      stillAvailable = true;
      undername = activeARNSRecords.first;
    } else {
      stillAvailable = false;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (stillAvailable ?? false) {
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
            child: ArDriveIcons.arnsName(size: 18),
          ),
        ),
      );
    } else {
      return const SizedBox();
    }
  }
}
