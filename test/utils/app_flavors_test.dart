import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

void main() {
  group('EnvFetcher getEnv on mobile', () {
    late EnvFetcher envFetcher;

    setUp(() {
      envFetcher = EnvFetcher();
    });

    test('should return env production', () async {
      mockFlavorsNativeRequest('production');

      final env = await envFetcher.getEnv();

      expect(env, 'production');
    });

    test('should return env development', () async {
      mockFlavorsNativeRequest('development');

      final env = await envFetcher.getEnv();

      expect(env, 'development');
    });

    test(
        'should return production when we get a null variable on --dart=define=environment',
        () async {
      mockFlavorsNativeRequest(null);

      final env = await envFetcher.getEnv();

      expect(env, 'production');
    });
  });

  group('AppFlavors', () {
    late EnvFetcher mockEnvFetcher;
    late AppFlavors appFlavors;

    setUp(() {
      mockEnvFetcher = MockEnvFetcher();
      appFlavors = AppFlavors(mockEnvFetcher);
    });

    test('should return production flavor', () async {
      when(() => mockEnvFetcher.getEnv()).thenAnswer((_) async => 'production');

      final flavor = await appFlavors.getAppFlavor();

      expect(flavor, Flavor.production);
    });

    test('should return development flavor', () async {
      when(() => mockEnvFetcher.getEnv())
          .thenAnswer((_) async => 'development');

      final flavor = await appFlavors.getAppFlavor();

      expect(flavor, Flavor.development);
    });

    test('should return production flavor when pass a different env', () async {
      when(() => mockEnvFetcher.getEnv()).thenAnswer((_) async => 'test');

      final flavor = await appFlavors.getAppFlavor();

      expect(flavor, Flavor.production);
    });
  });
}

void mockFlavorsNativeRequest(String? flavor) {
  const channel = MethodChannel('flavor');

  handler(MethodCall methodCall) async {
    if (methodCall.method == 'getFlavor') {
      return flavor;
    }
    return null;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}
