import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInfoServices().loadAppInfo();
  HttpClient.enableTimelineLogging = false;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ARFS File Upload Example')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: UploadForm(),
          ),
        ),
      ),
    );
  }
}

class UploadForm extends StatefulWidget {
  const UploadForm({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _UploadFormState createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  String _statusText = "Pick wallet";
  IOFile? walletFile;
  IOFile? file;
  IOFile? decryptedFile;
  UploadController controller = UploadController();
  final driveIdController = TextEditingController();
  final passwordController = TextEditingController();
  final parentFolderIdController = TextEditingController();
  String dropdownValue = 'public';

  Future<String> pickWallet() async {
    final walletFile =
        await ArDriveIO().pickFile(fileSource: FileSource.fileSystem);

    setState(() {
      this.walletFile = walletFile;
      _statusText = "Wallet selected";
    });

    return walletFile.path;
  }

  Future<String> pickFile() async {
    final file = await ArDriveIO().pickFiles(fileSource: FileSource.fileSystem);

    setState(() {
      this.file = file.first;
      _statusText = "File selected";
    });

    return file.first.path;
  }

  static const keyByteLength = 256 ~/ 8;

  void _uploadFile() async {
    final uploader = ArDriveUploader();

    setState(() {
      _statusText = "Uploading File...";
    });

    final wallet = Wallet.fromJwk(
      json.decode(
        await walletFile!.readAsString(),
      ),
    );
    SecretKey? driveKey;

    if (dropdownValue == 'private') {
      final kdf = Hkdf(hmac: Hmac(Sha256()), outputLength: keyByteLength);

      final driveIdBytes = Uuid.parse(driveIdController.text);

      final walletSignature = await wallet
          .sign(Uint8List.fromList(utf8.encode('drive') + driveIdBytes));

      const password = '123';

      driveKey = await kdf.deriveKey(
        secretKey: SecretKey(walletSignature),
        info: utf8.encode(password),
        nonce: Uint8List(1),
      );

      // print('driveKey: ${await driveKey.extract()..toString()}');
    }

    controller = await uploader.upload(
      file: file!,
      driveKey: driveKey,
      args: ARFSUploadMetadataArgs(
        driveId: driveIdController.text,
        parentFolderId: parentFolderIdController.text,
        isPrivate: false,
      ),
      wallet: wallet,
    );

    controller.progressStream.listen((event) {
      setState(() {
        _statusText = 'Uploading file... ${event.toStringAsFixed(2)}%';
      });
    });

    setState(() {
      _statusText = 'File uploaded';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: pickWallet,
          child: const Text("Select wallet"),
        ),
        if (walletFile != null) ...[
          TextField(
            controller: driveIdController,
            onChanged: (value) {
              setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'Drive ID',
            ),
          ),
          if (driveIdController.text.isNotEmpty) ...[
            TextField(
              controller: parentFolderIdController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: const InputDecoration(
                labelText: 'Parent Folder ID',
              ),
            ),
            if (parentFolderIdController.text.isNotEmpty) ...[
              ElevatedButton(
                onPressed: () async {
                  await pickFile();
                },
                child: const Text("Select file"),
              ),
            ],
          ],
        ],
        if (file != null) ...[
          DropdownButton<String>(
            value: dropdownValue,
            onChanged: (String? newValue) {
              setState(() {
                dropdownValue = newValue!;
              });
            },
            items: <String>['public', 'private']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value.toUpperCase()),
              );
            }).toList(),
          ),
          if (dropdownValue == 'private')
            TextField(
              controller: passwordController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: const InputDecoration(
                labelText: 'Drive Password',
              ),
            ),
          if (dropdownValue == 'public' ||
              passwordController.text.isNotEmpty) ...[
            ElevatedButton(
              onPressed: _uploadFile,
              child: const Text("Upload file"),
            ),
          ],
        ],
        Text(_statusText),
        ElevatedButton(
          onPressed: decryptFile,
          child: const Text("Decrypt file"),
        ),
        StreamBuilder<double>(
            stream: controller.progressStream,
            builder: (context, snapshot) {
              return Text(snapshot.data?.toStringAsFixed(2) ?? '');
            })
      ],
    );
  }

  Future<void> decryptFile() async {
    final wallet = Wallet.fromJwk(
      json.decode(
        await walletFile!.readAsString(),
      ),
    );

    final encryptedFile =
        await ArDriveIO().pickFile(fileSource: FileSource.fileSystem);

    final kdf = Hkdf(hmac: Hmac(Sha256()), outputLength: keyByteLength);

    final driveIdBytes = Uuid.parse(driveIdController.text);
    final walletSignature = await wallet
        .sign(Uint8List.fromList(utf8.encode('drive') + driveIdBytes));
    const password = '123';

    final fileIdBytes =
        Uint8List.fromList(Uuid.parse('ebdbce5b-6ce2-476d-ac26-51cdbd17f9d2'));

    final driveKey = await kdf.deriveKey(
      secretKey: SecretKey(walletSignature),
      info: utf8.encode(password),
      nonce: Uint8List(1),
    );

    final fileKey = await kdf.deriveKey(
      secretKey: driveKey,
      info: fileIdBytes,
      nonce: Uint8List(1),
    );

    final keyData = Uint8List.fromList(await fileKey.extractBytes());

    // final impl =
    // await cipherStreamEncryptImpl(Cipher.aes256ctr, keyData: keyData);

    final cipherIv = decodeBase64ToBytes('5_JZjWhjVK2zHsx9');

    final decrypted = await decryptTransactionDataStream(
      Cipher.aes256ctr,
      cipherIv,
      encryptedFile.openReadStream(),
      keyData,
      await encryptedFile.length,
    );

    final Uint8List combinedData = await streamToUint8List(decrypted);

    ArDriveIO().saveFile(await IOFile.fromData(combinedData,
        name: 'decryptedfile.png',
        lastModifiedDate: DateTime.now(),
        contentType: 'image/png'));
  }
}

Future<Uint8List> streamToUint8List(Stream<Uint8List> stream) async {
  List<Uint8List> collectedData = await stream.toList();
  int totalLength =
      collectedData.fold(0, (prev, element) => prev + element.length);

  final result = Uint8List(totalLength);
  int offset = 0;

  for (var data in collectedData) {
    result.setRange(offset, offset + data.length, data);
    offset += data.length;
  }

  return result;
}
