import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/blocs.dart';
import 'components/components.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  AppShell({Key key, this.page}) : super(key: key);

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesBloc, DrivesState>(
      builder: (context, state) {
        final content = Scaffold(
          body: Row(
            children: [
              AppDrawer(),
              VerticalDivider(width: 0),
              Expanded(
                child: widget.page,
              ),
            ],
          ),
        );

        return content;
      },
    );
  }
}
