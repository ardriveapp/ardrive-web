import 'dart:io';

import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// Turbo can't be reached: the bento leaves the price out.
class _MockPaymentService extends Mock implements PaymentService {}

/// Wavehaus, so the panel and the bento lay out with real letter widths
/// rather than the test font's squares.
Future<void> _loadWavehaus() async {
  Future<ByteData> read(String path) async =>
      ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
  ]) {
    wavehaus.addFont(read('$dir/$f'));
  }
  await wavehaus.load();
}

void main() {
  setUpAll(_loadWavehaus);

  // The bento and the sign-in panel side by side: one outer margin, so their
  // tops and bottoms line up and both sit the same distance in from the
  // window's edges.
  for (final size in const [
    Size(1440, 900),
    Size(1280, 900),
    Size(1280, 832),
    Size(1024, 900),
    Size(834, 900),
  ]) {
    testWidgets(
        'the bento and the panel line up at '
        '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
      final loginBloc = _MockLoginBloc();
      final profileNameBloc = _MockProfileNameBloc();
      final preferences = _MockUserPreferencesRepository();
      when(() => preferences.watch())
          .thenAnswer((_) => const Stream<UserPreferences>.empty());
      when(() => preferences.currentPreferences).thenReturn(null);
      whenListen(loginBloc, const Stream<LoginState>.empty(),
          initialState: const LoginEnterRecoveryPhrase());
      whenListen(profileNameBloc, const Stream<ProfileNameState>.empty(),
          initialState: const ProfileNameInitial(null));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<LoginBloc>.value(value: loginBloc),
            BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
            RepositoryProvider<UserPreferencesRepository>.value(
                value: preferences),
            RepositoryProvider<PaymentService>.value(
                value: _MockPaymentService()),
            BlocProvider<ThemeSwitcherBloc>(
              create: (_) =>
                  ThemeSwitcherBloc(userPreferencesRepository: preferences),
            ),
          ],
          child: ArDriveApp(
            builder: (context) => const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LoginPageScaffold(loginState: LoginEnterRecoveryPhrase()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      final bento = tester.getRect(find.byType(TilesView));
      // The panel's border box: the nearest Stack around the panel fills it,
      // inside its 1 px border.
      final panel = tester
          .getRect(find
              .ancestor(
                of: find.byKey(const Key('enterRecoveryPhraseView')),
                matching: find.byType(Stack),
              )
              .first)
          .inflate(1);

      expect(panel.top, bento.top, reason: 'tops');
      expect(panel.bottom, bento.bottom, reason: 'bottoms');
      final inset = bento.left;
      expect(size.width - panel.right, inset, reason: 'side insets');
      expect(bento.top, inset, reason: 'top inset');
      expect(size.height - bento.bottom, inset, reason: 'bottom inset');

      // The bento's timers run until it is gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
