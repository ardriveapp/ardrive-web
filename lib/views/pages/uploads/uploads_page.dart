import 'package:flutter/material.dart';

class UploadsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Scrollbar(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48.0),
                child: ListView.separated(
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  itemBuilder: (context, _) => ListTile(
                    dense: true,
                    leading: Icon(Icons.insert_drive_file),
                    title: Text('arweave.json'),
                    subtitle: Text('Personal • 35MB/401MB'),
                    trailing: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  separatorBuilder: (context, _) => Divider(),
                  itemCount: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
