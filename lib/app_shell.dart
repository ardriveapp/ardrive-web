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
    return BlocBuilder<DrivesCubit, DrivesState>(
      builder: (context, state) {
        final content = Scaffold(
          appBar: AppBar(
            title: Image.asset(
              'assets/images/logo-horiz-no-subtitle.png',
              height: 64,
              fit: BoxFit.contain,
            ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: CircleAvatar(),
                onPressed: null,
              ),
            ],
          ),
          body: Row(
            children: [
              AppDrawer(),
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
