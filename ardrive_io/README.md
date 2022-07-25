
# ArDriveIO
Standart library to perform I/O operations at ArDrive Web
## Features
The following methods performs the I/O operations supported in this package:

### Pick a file(s) or an folder on O.S.
- pickFile() 
- pickFiles()
- pickFolder()

### Save a file on O.S.
- saveFile()

## Getting started
Before using this package you should follow the follwing instrunctions

### Android
For pickFile(s) or folders nothing is required, but is worth to read the [file_picker Setup](https://github.com/miguelpruivo/flutter_file_picker/wiki/Setup#--android).

Add those permissions to AndroidManifest to be able to use the `saveFile()` function on Android.

```xml
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

### iOS
TODO: Explain the setup on iOS once we have the iOS implementation

### Web

## Usage
An example application is provided at `/example` folder.

It's easy to pick a file. It will opens the O.S. file picker and returns the `IOFile`.
```dart
final arDriveIO = ArDriveIO();

final file = await arDriveIO.pickFile();
```

It's possible to filter the files using the `allowedExtensions` parameter
```dart
final arDriveIO = ArDriveIO();

final file = await arDriveIO.pickFile(allowedExtensions: ['json']);
```

To pick a folder just need to call `pickFolders()` function 
```dart
final arDriveIO = ArDriveIO();

final folder = await arDriveIO.pickFolder();

```
To get its content, call `listContent()`, it will recursiverly mounts the folder hierachy returning the current folder structure in a tree of `IOEntity`s.
```dart
final arDriveIO = ArDriveIO();

final files = await folder.listContent();
```

It's possible to list all files or folders without handling the complexity of get it recursiverly with the methods
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
Base class for every file from / to O.S.

### IOFolder
Base class for every folder from O.S.
