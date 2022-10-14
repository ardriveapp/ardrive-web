import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppFlavors appFlavors;

  setUp(() {
    appFlavors = AppFlavors();
  });

  test('should return flavor production', () async {
    mockFlavorsNativeRequest('production');

    final flavor = await appFlavors.getAppFlavor();

    expect(flavor, Flavor.production);
  });

  test('should return flavor development', () async {
    mockFlavorsNativeRequest('development');

    final flavor = await appFlavors.getAppFlavor();

    expect(flavor, Flavor.development);
  });

  test('should throw when an unexpected flavor', () async {
    mockFlavorsNativeRequest('qa');

    expect(
      appFlavors.getAppFlavor(),
      throwsA(
        const TypeMatcher<UnsupportedError>(),
      ),
    );
  });
}

void mockFlavorsNativeRequest(String flavor) {
  const channel = MethodChannel('flavor');

  handler(MethodCall methodCall) async {
    if (methodCall.method == 'getFlavor') {
      return flavor;
    }
    return null;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance?.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}
