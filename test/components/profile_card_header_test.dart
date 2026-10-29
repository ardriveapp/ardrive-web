import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

/// The account button in the top bar, for a wallet with no name to show.
void main() {
  // Every letter of the test font is as wide as it is tall, so this address
  // stands in for one made of wide letters, the case that overran the button.
  const address = 'iKryOeAbCdEfGhIjKlMnOpQrStUvWxYz0123ncoRjA';

  late _MockProfileNameBloc profileNameBloc;

  setUp(() {
    profileNameBloc = _MockProfileNameBloc();
    when(() => profileNameBloc.state)
        .thenReturn(const ProfileNameLoadedWithWalletAddress(address));
  });

  Future<void> pumpHeader(WidgetTester tester) => tester.pumpWidget(
        ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: BlocProvider<ProfileNameBloc>.value(
                  value: profileNameBloc,
                  child: ProfileCardHeader(
                    walletAddress: address,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('shortens the address once, keeping its start and its end',
      (tester) async {
    await pumpHeader(tester);

    expect(find.text('iKryOe...oRjA'), findsOneWidget);

    // A second shortening is the button cutting the text short with its own
    // ellipsis, which drops the end of the address the first one kept.
    final paragraph =
        tester.renderObject<RenderParagraph>(find.text('iKryOe...oRjA'));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}
