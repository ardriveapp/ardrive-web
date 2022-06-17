export 'resources.dart';

const kDriveNameRegex = kFolderNameRegex;
const kFolderNameRegex = r'^[^\/\\\<\>\:\"\?\*]+$';
const kFileNameRegex = r'^[^\/\\\*]+$';
const kTrimTrailingRegex = r'[^\s \.]+$';
/* kTrimTrailingRegex was the only working way to do
    the check for trailing periods and spaced without using
    lookbehind in the file and folder name regex.
    Change back to previous regex with lookbehind when
    Safari supports it.
  */

const mempoolWarningSizeLimit = 1;
