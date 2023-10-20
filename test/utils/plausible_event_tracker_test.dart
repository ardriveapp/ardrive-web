import 'package:ardrive/utils/plausible_event_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPlausibleApi extends Mock implements PlausibleApi {}

void main() {
  group('PlausibleEventTracker class', () {
    group('trackPageView method', () {
      test('calls the track method of PlausibleApi', () async {
        final mockPlausibleApi = MockPlausibleApi();
        when(
          () => mockPlausibleApi.track(
            pageName: any(named: 'pageName'),
            customEventName: any(named: 'customEventName'),
          ),
        ).thenAnswer((_) async {});

        await PlausibleEventTracker.trackPageView(
          page: ArDrivePage.fileExplorer,
          plausibleApi: mockPlausibleApi,
        );

        verify(
          () => mockPlausibleApi.track(
            pageName: ArDrivePage.fileExplorer.name,
          ),
        ).called(1);
      });
    });

    group('trackCustomEvent method', () {
      test('calls the track method of PlausibleApi', () async {
        final mockPlausibleApi = MockPlausibleApi();
        when(
          () => mockPlausibleApi.track(
            pageName: any(named: 'pageName'),
            customEventName: any(named: 'customEventName'),
          ),
        ).thenAnswer((_) async {});

        await PlausibleEventTracker.trackCustomEvent(
          page: ArDrivePage.fileExplorer,
          event: ArDriveEvent.fileExplorerLoggedInUser,
          plausibleApi: mockPlausibleApi,
        );

        verify(
          () => mockPlausibleApi.track(
            // Yes, it does fake a page view to the event name for now.
            pageName: ArDriveEvent.fileExplorerLoggedInUser.name,
          ),
        ).called(1);
      });
    });
  });
}
