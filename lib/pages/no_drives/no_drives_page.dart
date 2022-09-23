import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/new_button.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  const NoDrivesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => ScreenTypeLayout(
        desktop: Center(
          child: Text(
            appLocalizationsOf(context).noDrives,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headline6,
          ),
        ),
        mobile: Stack(
          children: [
            Center(
              child: Text(
                appLocalizationsOf(context).noDrives,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headline6,
              ),
            ),
            if (!kIsWeb)
              BlocBuilder<DrivesCubit, DrivesState>(
                builder: (context, drivesState) =>
                    BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, profileState) =>
                      BlocBuilder<DriveDetailCubit, DriveDetailState>(
                    builder: (context, driveDetailState) => Positioned(
                      bottom: 16,
                      right: 16,
                      child: buildNewButton(
                        context,
                        drivesState: drivesState,
                        profileState: profileState,
                        driveDetailState: driveDetailState,
                        isPlusButton: true,
                        button: const FloatingActionButton.extended(
                          extendedPadding: EdgeInsets.zero,
                          shape: CircleBorder(),
                          label: Icon(
                            Icons.add,
                            size: 40,
                          ),
                          onPressed: null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
