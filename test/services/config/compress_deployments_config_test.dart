import 'dart:convert';
import 'dart:io';

import 'package:ardrive/services/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig _flavor(String name) => AppConfig.fromJson(
      jsonDecode(File('assets/config/$name.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void main() {
  group('compressDeployments', () {
    test('is on in every flavour', () {
      expect(_flavor('dev').compressDeployments, isTrue);
      expect(_flavor('staging').compressDeployments, isTrue);
      expect(_flavor('prod').compressDeployments, isTrue);
    });

    test('is written in every flavour, so turning it on is a one-line change',
        () {
      for (final name in ['dev', 'staging', 'prod']) {
        final json =
            jsonDecode(File('assets/config/$name.json').readAsStringSync())
                as Map<String, dynamic>;
        expect(json.containsKey('compressDeployments'), isTrue, reason: name);
      }
    });

    test('is off for a config stored before the key existed', () {
      final json = jsonDecode(File('assets/config/dev.json').readAsStringSync())
          as Map<String, dynamic>
        ..remove('compressDeployments');
      expect(AppConfig.fromJson(json).compressDeployments, isFalse);
    });

    test('survives a round trip through the stored form and copyWith', () {
      final config = _flavor('dev');
      expect(
          AppConfig.fromJson(jsonDecode(jsonEncode(config.toJson()))
                  as Map<String, dynamic>)
              .compressDeployments,
          isTrue);
      expect(config.copyWith(compressDeployments: false).compressDeployments,
          isFalse);
      expect(config.copyWith(configVersion: 99).compressDeployments, isTrue);
    });
  });
}
