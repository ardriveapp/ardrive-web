import 'package:json_annotation/json_annotation.dart';

part 'plausible_custom_event_properties.g.dart';

@JsonSerializable()
class AppLoadedProperties {
  @JsonKey(name: 'App Version')
  String appVersion;
  @JsonKey(name: 'Platform')
  String platform;
  @JsonKey(name: 'Platform Version')
  String platformVersion;

  AppLoadedProperties({
    required this.appVersion,
    required this.platform,
    required this.platformVersion,
  });

  factory AppLoadedProperties.fromJson(Map<String, dynamic> json) =>
      _$AppLoadedPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$AppLoadedPropertiesToJson(this);
}

@JsonSerializable()
class NewButtonProperties {
  @JsonKey(name: 'Location')
  NewButtonLocation location;

  NewButtonProperties({
    required this.location,
  });

  factory NewButtonProperties.fromJson(Map<String, dynamic> json) =>
      _$NewButtonPropertiesFromJson(json);
  Map<String, dynamic> toJson() => _$NewButtonPropertiesToJson(this);
}

enum NewButtonLocation {
  bottom,
  sidebar,
}
