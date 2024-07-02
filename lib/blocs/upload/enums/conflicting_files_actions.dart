/// Actions that the user can take to handle conflicting files.
///
/// `Skip` Will ignore the files and don't upload them.
///
/// `Replace` will upload the conflicting file and replace the existent.
///
/// `SkipSuccessfullyUploads` will skip the files that were successfully uploaded.
enum UploadActions { skip, skipSuccessfulUploads, replace }
