import 'package:flutter/material.dart';

import 'components.dart';

Future<void> showInputSeedphraseDialog({
  required BuildContext context,
  required Function(List<String> mnemonic) onConfirmMnemonic,
}) {
  final List<String> seedphrase = List.filled(12, '');
  return showDialog(
    context: context,
    builder: (context) {
      return AppDialog(
        title: 'Generate Seedphrase',
        content: SizedBox(
          width: MediaQuery.of(context).size.width / 1.8,
          height: MediaQuery.of(context).size.height / 3,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Please enter your seed phrase by entering the words in the correct order.',
                ),
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (int i = 0; i < 12; i++)
                          Container(
                            height: 48,
                            width: 128,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  alignment: Alignment.center,
                                  width: 32,
                                  height: 48,
                                  color: Colors.black,
                                  child: Text(
                                    (i + 1).toString(),
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    onChanged: ((value) {
                                      seedphrase[i] = value;
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(
                  height: 32,
                ),
                ElevatedButton(
                  onPressed: () {
                    onConfirmMnemonic(seedphrase);
                  },
                  child: Text('CONFIRM'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
