export 'resources.dart';

const kDriveNameRegex = kFolderNameRegex;
const kFolderNameRegex = r'^[^\/\\\<\>\:\"\?]+(?<!\.)$';
const kFileNameRegex = r'^[^\/\\]+(?<!\.)$';
