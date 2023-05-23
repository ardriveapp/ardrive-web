import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:equatable/equatable.dart';

class UserPreferences extends Equatable {
  final ArDriveThemes currentTheme;

  const UserPreferences({
    required this.currentTheme,
  });

  @override
  List<Object?> get props => [currentTheme.name];
}
