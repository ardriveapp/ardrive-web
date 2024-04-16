import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

BoxShadow _boxShadow20(ArDriveColors colors) => BoxShadow(
      color: colors.shadow,
      offset: const Offset(0, 0),
      blurRadius: 1,
    );
BoxShadow _boxShadow40(ArDriveColors colors) => BoxShadow(
      color: colors.shadow,
      offset: const Offset(0, 2),
      blurRadius: 4,
    );
BoxShadow _boxShadow60(ArDriveColors colors) => BoxShadow(
      color: colors.shadow,
      offset: const Offset(0, 4),
      blurRadius: 8,
    );
BoxShadow _boxShadow80(ArDriveColors colors) => BoxShadow(
      color: colors.shadow,
      offset: const Offset(0, 8),
      blurRadius: 16,
    );
BoxShadow _boxShadow100(ArDriveColors colors) => BoxShadow(
      color: colors.shadow,
      offset: const Offset(0, 16),
      blurRadius: 24,
    );

class ArDriveShadows {
  ArDriveShadows(this.colors);

  final ArDriveColors colors;

  BoxShadow boxShadow20() => _boxShadow20(colors);
  BoxShadow boxShadow40() => _boxShadow40(colors);
  BoxShadow boxShadow60() => _boxShadow60(colors);
  BoxShadow boxShadow80() => _boxShadow80(colors);
  BoxShadow boxShadow100() => _boxShadow100(colors);
}
