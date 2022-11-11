import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart' show MockAppFlavors;

void main() {
  late ConfigService configService;
  late AppFlavors mockAppFlavors;

  setUp(() {
    mockAppFlavors = MockAppFlavors();
    configService = ConfigService(appFlavors: mockAppFlavors);
  });

  group('testing getAppFlavors method', () {
    test('should return production flavor', () async {
      // arrange
      when(() => mockAppFlavors.getAppFlavor()).thenAnswer(
        (invocation) => Future.value(Flavor.production),
      );
      // act
      final flavor = await configService.getAppFlavor();

      // assert
      expect(flavor, Flavor.production);
    });

    test('should return development flavor', () async {
      // arrange
      when(() => mockAppFlavors.getAppFlavor()).thenAnswer(
        (invocation) => Future.value(Flavor.development),
      );
      // act
      final flavor = await configService.getAppFlavor();

      // assert
      expect(flavor, Flavor.development);
    });

    test('should return production flavor when AppFlavors throws', () async {
      // arrange
      when(() => mockAppFlavors.getAppFlavor()).thenThrow(
        UnsupportedError('some flavor not expected'),
      );
      // act
      final flavor = await configService.getAppFlavor();

      // assert
      expect(flavor, Flavor.production);
    });
  });
}
