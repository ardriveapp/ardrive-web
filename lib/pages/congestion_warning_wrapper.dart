import 'package:ardrive/components/components.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showCongestionWarning(
    BuildContext context, Future<void> dialog) async {
  final warnOrUpload = await context.read<ArweaveService>().getMempoolsize() >
      mempoolWarningSizeLimit;
  var proceedWithUpload = true;
  if (warnOrUpload) {
    await showDialog(
      context: context,
      builder: (_) => AppDialog(
        title: 'WARNING',
        content: SizedBox(
          width: kMediumDialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                              text:
                                  'Arweave is currently experiencing heavy congestion. '
                                  'It\'s not likely that your upload will succeed right now.'),
                        ],
                        style: Theme.of(context).textTheme.bodyText1,
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              proceedWithUpload = false;
              Navigator.of(context).pop(false);
            },
            child: Text('TRY LATER'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('PROCEED'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }
  if (proceedWithUpload) {
    return dialog;
  }
}
