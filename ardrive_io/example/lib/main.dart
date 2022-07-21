import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ArDriveIOExample(),
    );
  }
}

class ArDriveIOExample extends StatefulWidget {
  const ArDriveIOExample({Key? key}) : super(key: key);

  @override
  State<ArDriveIOExample> createState() => _ArDriveIOExampleState();
}

class _ArDriveIOExampleState extends State<ArDriveIOExample> {
  String? fileDescription;
  IOFile? currentFile;
  IOFolder? currentFolder;

  Future<void> pickFile() async {
    final file = await ArDriveIO().pickFile();

    setState(() {
      currentFile = file;
      print(currentFile.toString());
      currentFolder = null;
    });
  }

  Future<void> pickFolder() async {
    final folder = await ArDriveIO().pickFolder();
    
    setState(() {
      currentFolder = folder;
      currentFile = null;
    });
  }

  Future<void> saveFile(BuildContext context) async {
    // creates a new file and save on O.S.
    await ArDriveIO().saveFile(currentFile!);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('File saved')));

    setState(() {
      currentFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
            '${currentFile != null ? currentFile!.name : currentFolder != null ? currentFolder!.name : 'ArDriveIO'} '),
      ),
      body: Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(fileDescription ?? ''),
              ElevatedButton(
                  onPressed: () async {
                    await pickFile();
                  },
                  child: const Text('Pick file')),
              ElevatedButton(
                  onPressed: () async {
                    await pickFolder();
                  },
                  child: const Text('Pick folder')),
              if (currentFile != null)
                ElevatedButton(
                    onPressed: () async {
                      await saveFile(context);
                    },
                    child: const Text('save file')),
            ]),
      ),
    );
  }
}
