export 'resources.dart';

const kDriveNameRegex = kFolderNameRegex;
const kFolderNameRegex = r'^[a-zA-Zа-яА-Я0-9-_\s.!]+[^\s.\/\\]$';
const kFileNameRegex = r'^[^\\\/]+[^\s.\/\\]$';
