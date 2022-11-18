import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/components/listtile.dart';
import 'package:flutter/material.dart';

class ArDriveDataTable extends StatefulWidget {
  final List<List<Widget>> rows;
  final List<Widget> columns;

  const ArDriveDataTable({
    super.key,
    required this.rows,
    required this.columns,
  });

  @override
  State<ArDriveDataTable> createState() => _ArDriveDataTableState();
}

class _ArDriveDataTableState extends State<ArDriveDataTable> {
  int? selectedIndex;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 84,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: widget.columns.first,
                    ),
                  ),
                  ...widget.columns
                      .sublist(1)
                      .map((column) => Flexible(child: column)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemBuilder: (context, index) {
                  return ArDriveListTile(
                    selected: index == selectedIndex ? true : false,
                    onTap: () {
                      setState(() {
                        if (selectedIndex != index) {
                          selectedIndex = index;
                        } else {
                          selectedIndex = null;
                        }
                      });
                    },
                    title: SizedBox(
                      height: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            flex: 2,
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 28),
                                child: widget.rows[index].first),
                          ),
                          ...widget.rows[index]
                              .sublist(1)
                              .map((cell) => Flexible(child: cell)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
