import 'package:ardrive/components/new_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/blocs.dart';

class PlusButton extends StatelessWidget {
  const PlusButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return BlocBuilder<DrivesCubit, DrivesState>(
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
      );
    }
    return const SizedBox.shrink();
  }
}
