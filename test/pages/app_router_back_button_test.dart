import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

/// The real delegate's routing, under a real [Router], with only its page
/// tree swapped for one that needs no app around it.
class _BareRouterDelegate extends AppRouterDelegate {
  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: [
          MaterialPage(
            child: Text(signingIn ? 'sign in' : 'page'),
          ),
        ],
        onPopPage: (route, result) => route.didPop(result),
      );
}

/// A visitor at `#/` is sent to sign in. That is reported to the browser as a
/// replace of `#/`, not as a new entry: as a push, Back from `#/sign-in` went
/// to `#/`, which sent them to `#/sign-in` again, and Back never left.
void main() {
  testWidgets('Back to / from a share page replaces / with /sign-in',
      (tester) async {
    final reports = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          reports.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null));

    final profile = MockProfileCubit();
    when(() => profile.state).thenReturn(ProfilePromptAdd());
    final delegate = _BareRouterDelegate()..profileCubit = profile;
    final provider = PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(
        uri: Uri.parse('/file/4752318f-2bdc-4aa9-b428-4e1cf5808bcf/view'),
      ),
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(MaterialApp.router(
      routerDelegate: delegate,
      routeInformationParser: AppRouteInformationParser(),
      routeInformationProvider: provider,
    ));
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    reports.clear();

    // What the browser hands the app on Back, or on `#/` typed in.
    provider.didPushRouteInformation(RouteInformation(uri: Uri.parse('/')));
    await tester.pumpAndSettle();

    expect(find.text('sign in'), findsOneWidget);
    expect(reports, isNotEmpty);
    expect(reports.last['uri'], '/sign-in');
    expect(reports.last['replace'], isTrue);
  });
}
