import 'package:ardrive/components/new_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/blocs.dart';

/// Renders a Plus ("+") Button that opens the same menu than the New Button
///
/// **Note** In order for this Widget to be placed positioned absolute to the whole
/// screen it needs to be (grand)child of a Stack widget.
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
