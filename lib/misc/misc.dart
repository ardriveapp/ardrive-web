export 'resources.dart';

const kDriveNameRegex = kFolderNameRegex;
const kFolderNameRegex = r'^[a-zA-Zа-яА-Я0-9_\s.!]+[^\s.\/\\]$';
const kFileNameRegex = r'^[^\\\/]+[^\s.\/\\]$';
