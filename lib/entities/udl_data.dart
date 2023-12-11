import 'dart:convert';
import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

part 'udl_data.g.dart';

enum UdlDerivationType {
  unspecified,
  allowed,
  allowedWithProfitShare,
}

@JsonSerializable()
class UdlDerivation {
  @JsonKey()
  final UdlDerivationType type;
  @JsonKey()
  final String? revenueSharePercentage;

  UdlDerivation(this.type, this.revenueSharePercentage);

  factory UdlDerivation.fromJson(Map<String, dynamic> json) =>
      _$UdlDerivationFromJson(json);
  Map<String, dynamic> toJson() => _$UdlDerivationToJson(this);
}

@JsonSerializable(explicitToJson: true)
class UdlData {
  @JsonKey()
  final UdlDerivation derivation;

  UdlData(this.derivation);

  int get size => jsonData.lengthInBytes;
  Uint8List get jsonData => utf8.encode(json.encode(this)) as Uint8List;

  factory UdlData.fromJson(Map<String, dynamic> json) =>
      _$UdlDataFromJson(json);
  Map<String, dynamic> toJson() => _$UdlDataToJson(this);
}
