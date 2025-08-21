import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as x;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  TextEditingController textEditingController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('File Saver'),
        ),
        body: Column(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: textEditingController,
                  decoration: const InputDecoration(
                      labelText: "Name",
                      hintText: "Something",
                      border: OutlineInputBorder()),
                ),
              ),
            ),
            ElevatedButton(
                onPressed: () async {
                  if (!kIsWeb) {
                    if (Platform.isIOS ||
                        Platform.isAndroid ||
                        Platform.isMacOS) {
                      bool status = await Permission.storage.isGranted;

                      if (!status) await Permission.storage.request();
                    }
                  }
                  final x.Workbook workbook = x.Workbook();
                  final x.Worksheet excel =
                      workbook.worksheets.addWithName('Sheet1');
                  excel.insertColumn(1, 3);
                  for (int i = 1; i < 10; i++) {
                    excel.insertRow(i);
                  }
                  List<int> sheets = workbook.saveAsStream();

                  workbook.dispose();
                  Uint8List data = Uint8List.fromList(sheets);
                  MimeType type = MimeType.MICROSOFTEXCEL;
                  String path = await FileSaver.instance.saveFile(
                      textEditingController.text == ""
                          ? "File"
                          : textEditingController.text,
                      data,
                      "xlsx",
                      mimeType: type);
                  log(path);
                },
                child: const Text("Save File")),
            if (!kIsWeb)
              if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
                ElevatedButton(
                  onPressed: () async {
                    final x.Workbook workbook = x.Workbook();
                    final x.Worksheet excel =
                        workbook.worksheets.addWithName('Sheet1');
                    excel.insertColumn(1, 3);
                    for (int i = 1; i < 10; i++) {
                      excel.insertRow(i);
                    }
                    List<int> sheets = workbook.saveAsStream();
                    workbook.dispose();
                    Uint8List data = Uint8List.fromList(sheets);
                    MimeType type = MimeType.OTHER;
                    String path = await FileSaver.instance.saveAs(
                        textEditingController.text == ""
                            ? "File"
                            : textEditingController.text,
                        data,
                        "custome123",
                        type);
                    log(path);
                  },
                  child: const Text("Generate Excel and Open Save As Dialog"),
                )
          ],
        ),
      ),
    );
  }
}
