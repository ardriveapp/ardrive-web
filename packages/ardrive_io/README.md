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

It's important to check the complete setup for using file_picker library at (setup iOS)[https://github.com/miguelpruivo/flutter_file_picker/wiki/Setup#ios]. Most of the information here is from file_picker documentation.

These Settings are optional for iOS, as in iOS the file will be saved in application documents directory but will not be visible in Files application, to make your file visible in iOS Files application, make the changes mentioned below.
iOS:

Go to your project folder, ios/Runner/info.plist and Add these keys:

Based on the location of the files that you are willing to pick paths, you may need to add some keys to your iOS app's Info.plist file, located in <project root>/ios/Runner/Info.plist:

#### UIBackgroundModes with the fetch and remote-notifications keys

Required if you'll be using the FileType.any or FileType.custom. Describe why your app needs to access background taks, such downloading files (from cloud services). This is called Required background modes, with the keys App download content from network and App downloads content in response to push notifications respectively in the visual editor (since both methods aren't actually overriden, not adding this property/keys may only display a warning, but shouldn't prevent its correct usage).

```xml
<key>UIBackgroundModes</key>
<array>
   <string>fetch</string>
   <string>remote-notification</string>
</array>
```

#### NSAppleMusicUsageDescription

Required if you'll be using the FileType.audio. Describe why your app needs permission to access music library. This is called Privacy - Media Library Usage Description in the visual editor.

```xml
<key>NSAppleMusicUsageDescription</key>
<string>Explain why your app uses music</string>
```

#### LSSupportsOpeningDocumentsInPlace

Required

```xml
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

#### UISupportsDocumentBrowser

Required if you'll want to write directly on directories. This way iOS creates an app folder for the app and the user can create and pick directories within the folder and the app has the permission to write here.

```xml
<key>UISupportsDocumentBrowser</key>
<true/>
```

#### NSPhotoLibraryUsageDescription

Required if you'll be using the FileType.image or FileType.video. Describe why your app needs permission for the photo library. This is called Privacy - Photo Library Usage Description in the visual editor.

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Explain why your app uses photo library</string>
```

#### UIFileSharingEnabled

Required to use the `save` method on iOS

```xml
<key>UIFileSharingEnabled</key>
<true/>
```

### Web

TODO:

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
