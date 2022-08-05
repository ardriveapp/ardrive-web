import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/url_launcher.dart';

/// [SharedFilePage] displays details of a shared file and controls for downloading and previewing it
/// from a parent [SharedFileCubit].
class SharedFilePage extends StatelessWidget {
  const SharedFilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kMediumDialogWidth,
          minWidth: kMediumDialogWidth,
          minHeight: 256,
        ),
        child: Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: BlocBuilder<SharedFileCubit, SharedFileState>(
              builder: (context, state) => Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    Resources.images.brand.logoHorizontalNoSubtitleLight,
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),
                  if (state is SharedFileIsPrivate) ...[
                    Text(appLocalizationsOf(context).sharedFileIsEncrypted),
                    const SizedBox(height: 16),
                    ReactiveForm(
                      formGroup: context.watch<SharedFileCubit>().form,
                      child: ReactiveTextField(
                        formControlName: 'fileKey',
                        autofocus: true,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: appLocalizationsOf(context).enterFileKey,
                        ),
                        validationMessages: (_) =>
                            kValidationMessages(appLocalizationsOf(context)),
                        onEditingComplete: () => context
                            .read<SharedFileCubit>()
                            .form
                            .updateValueAndValidity(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.read<SharedFileCubit>().submit(),
                      child: Text(appLocalizationsOf(context).unlock),
                    ),
                  ],
                  if (state is SharedFileLoadInProgress)
                    const CircularProgressIndicator()
                  else if (state is SharedFileLoadSuccess) ...{
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.text_snippet),
                      title: Text(state.file.name!),
                      subtitle: Text(filesize(state.file.size)),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_download),
                      label: Text(appLocalizationsOf(context).download),
                      onPressed: () => promptToDownloadSharedFile(
                        context: context,
                        fileId: state.file.id!,
                        fileKey: state.fileKey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildReturnToAppLink(context),
                  } else if (state is SharedFileNotFound) ...{
                    const Icon(Icons.error_outline, size: 36),
                    const SizedBox(height: 16),
                    Text(
                      appLocalizationsOf(context).specifiedFileDoesNotExist,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _buildReturnToAppLink(context),
                  }
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnToAppLink(BuildContext context) => TextButton(
        onPressed: () => launch('https://ardrive.io/'),
        child: Text(appLocalizationsOf(context).whatIsArDrive),
      );
}
