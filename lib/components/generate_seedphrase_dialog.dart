import 'package:bip39/bip39.dart';
import 'package:flutter/material.dart';

import 'components.dart';

Future<void> showGenerateSeedphraseDialog({
  required BuildContext context,
  required Function(List<String> seedphrase) onGenerateMnemonic,
}) {
  final seedphrase = generateMnemonic().split(' ');
  int seedIndex = 1;
  return showDialog(
    context: context,
    builder: (context) {
      return AppDialog(
        title: 'Generate Seedphrase',
        content: SizedBox(
          width: MediaQuery.of(context).size.width / 1.8,
          height: MediaQuery.of(context).size.height / 2,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                    'We are now creating your wallet. Please carefully write your seed phrase, in this order, and keep it somewhere safe.'),
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (int i = 0; i < seedphrase.length; i++)
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
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(seedphrase[i]),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Text(
                    'Anyone with your seedphrase will be able to access your drive and funds. Please confirm your seedphrase on the next screen.'),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: () {
                      onGenerateMnemonic(seedphrase);
                    },
                    child: Container(
                      width: 224,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const Text('I\'ve written it down'),
                          const Icon(Icons.arrow_forward),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
