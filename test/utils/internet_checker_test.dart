import 'package:ardrive/utils/internet_checker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  group('InternetChecker', () {
    late MockConnectivity mockConnectivity;
    late InternetChecker checker;

    setUp(() {
      mockConnectivity = MockConnectivity();
      checker = InternetChecker(connectivity: mockConnectivity);
    });

    test('should return true if connected to internet', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.mobile);
      expect(await checker.isConnected(), isTrue);
    });

    test('should return true if connected to internet', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.wifi);
      expect(await checker.isConnected(), isTrue);
    });

    test('should return false if not connected to internet', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.none);
      expect(await checker.isConnected(), isFalse);
    });
  });
}
