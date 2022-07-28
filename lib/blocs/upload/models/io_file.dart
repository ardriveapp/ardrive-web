// import 'dart:typed_data';

// // Use the crossfile package instead to make this suitable for use with mobile
// import 'package:file_selector/file_selector.dart';

// import 'upload_file.dart';

// class IOFile extends UploadFile {
//   final XFile file;
//   @override
//   final DateTime lastModifiedDate;
//   @override
//   final int size;

//   @override
//   final String parentFolderId;

//   IOFile._create(
//     this.file,
//     this.lastModifiedDate,
//     this.size,
//     this.parentFolderId,
//   ) : super(
//           name: file.name,
//           path: file.path,
//           lastModifiedDate: lastModifiedDate,
//           size: size,
//           parentFolderId: parentFolderId,
//         );

//   static Future<IOFile> fromXFile(XFile file, String parentFolderId) async {
//     final fileLastModified = await file.lastModified();
//     final fileSize = await file.length();

//     return IOFile._create(
//       file,
//       fileLastModified,
//       fileSize,
//       parentFolderId,
//     );
//   }

//   @override
//   Future<Uint8List> readAsBytes() => file.readAsBytes();

//   @override
//   String getIdentifier() {
//     return path.isEmpty || _isPathBlobFromDragAndDrop(path) ? name : path;
//   }

//   bool _isPathBlobFromDragAndDrop(String path) {
//     return path.split(':')[0] == 'blob';
//   }
// }
