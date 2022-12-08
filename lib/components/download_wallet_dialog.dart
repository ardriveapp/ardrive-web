import 'dart:async';

import 'package:ardrive/theme/theme.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';

import 'components.dart';

Future<void> showDownloadWalletDialog({
  required BuildContext context,
  required Function(Wallet) onWalletGenerated,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return DownloadWalletDialog(
        onWalletGenerated: onWalletGenerated,
      );
    },
  );
}

class DownloadWalletDialog extends StatefulWidget {
  final Function(Wallet) onWalletGenerated;

  const DownloadWalletDialog({super.key, required this.onWalletGenerated});

  @override
  State<DownloadWalletDialog> createState() => _DownloadWalletDialogState();
}

class _DownloadWalletDialogState extends State<DownloadWalletDialog> {
  bool? confirmed = false;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Download Wallet',
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Download and save your wallet file'),
            const SizedBox(
              height: 16,
            ),
            if (loading)
              SizedBox(
                height: 64,
                width: 64,
                child: CircularProgressIndicator(),
              )
            else
              Icon(
                Icons.cloud_download_outlined,
                size: 64,
              ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Nobody (including the ArDrive core team) can help you recover your wallet if the key file is lost. So, remember to keep it safe!',
            ),
            const SizedBox(
              height: 16,
            ),
            CheckboxListTile(
              value: confirmed,
              onChanged: (value) => setState(() {
                confirmed = value;
              }),
              title: Text(
                'I understand that no one can help me recover this if I lose it.',
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (confirmed ?? false) {
                    loading = true;
                    Wallet.generate().then(
                      (wallet) {
                        widget.onWalletGenerated(wallet);
                        // ignore: use_build_context_synchronously
                      },
                    );
                  }
                });
              },
              child: Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}
