import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/link.dart';

/// [SharedFilePage] displays details of a shared file and controls for downloading and previewing it
/// from a parent [SharedFileCubit].
class SharedFilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
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
                      R.images.brand.logoVerticalNoSubtitle,
                      height: 96,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 32),
                    if (state is SharedFileLoadInProgress)
                      const CircularProgressIndicator()
                    else if (state is SharedFileLoadSuccess) ...{
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.text_snippet),
                        title: Text(state.file.name),
                        subtitle: Text(filesize(state.file.size)),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: Icon(Icons.file_download),
                        label: Text('Download'),
                        onPressed: () => promptToDownloadSharedFile(
                          context: context,
                          fileId: state.file.id,
                          fileKey: state.fileKey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildReturnToAppLink(),
                    } else if (state is SharedFileNotFound) ...{
                      const Icon(Icons.error_outline, size: 36),
                      const SizedBox(height: 16),
                      Text(
                        'The specified file does not exist.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _buildReturnToAppLink(),
                    }
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildReturnToAppLink() => Link(
        uri: Uri(path: '/sign-in'),
        builder: (context, onPressed) => TextButton(
          child: Text('Go to app'),
          onPressed: onPressed,
        ),
      );
}
