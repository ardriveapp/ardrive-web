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
  Future<void> pickFile() async {
    final file = await ArDriveIO().pickFile();

    setState(() {
      fileDescription = file.name;
    });

    await ArDriveIO().saveFile(file);
  }

  Future<void> pickFolder() async {
    final folder = await ArDriveIO().pickFolder();
    final children = await folder.listContent();

    for (var entity in children) {
      if (entity is IOFile) {
        print(await entity.readAsBytes()
          ..length);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
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
          ]),
    );
  }
}
