
# ArDriveIO
Custom library to perform I/O operations for ArDrive Web
## Features
The following methods perform the I/O operations supported in this package:

### Pick a folder, a file or multiple files from the native storage
- pickFile()
- pickFiles()
- pickFolder()

### Save a file to the native storage
- saveFile()

## Getting started
In order to use this package you must follow these instructions:

### Android
For pickFile(s) or folders nothing is required, but is worth to read the [file_picker Setup](https://github.com/miguelpruivo/flutter_file_picker/wiki/Setup#--android).

Add those permissions to AndroidManifest

```xml
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

### iOS
TODO: Explain the setup on iOS once we have the iOS implementation

### Web

## Usage
An example application is provided at `/example` folder.

It's easy to pick a file. It will opens the native file picker and returns an `IOFile`.

```dart
final arDriveIO = ArDriveIO();

final file = await arDriveIO.pickFile();
```

It's possible to filter the files by using the `allowedExtensions` parameter

```dart
final arDriveIO = ArDriveIO();

final file = await arDriveIO.pickFile(allowedExtensions: ['json']);
```

To pick a folder you just need to call the `pickFolder()` function

```dart
final arDriveIO = ArDriveIO();

final folder = await arDriveIO.pickFolder();

```
To get its content, call `listContent()`. It will recursively mount the folder hierarchy and return the folder structure as a tree of `IOEntity`s.

```dart
final arDriveIO = ArDriveIO();

final folder = await arDriveIO.pickFolder();
final files = await folder.listContent();
```

It's possible to list all files and folders without handling the complexity of getting it recursively with the methods
`listFiles()` and `listSubfolders()`:
```dart

final arDriveIO = ArDriveIO();

final folder = await arDriveIO.pickFolder();
/// A list of all files inside this folder
final files = await folder.listFiles();
/// A list of all subfolders
final subfolders = await folder.listSubfolders();
```

## Additional information

### IOFile
Base class representing a local File

### IOFolder
Base class represeting a local Directory
