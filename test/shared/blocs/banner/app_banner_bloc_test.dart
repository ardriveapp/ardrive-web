import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/shared/blocs/banner/app_banner_bloc.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLocalKeyValueStore extends Mock implements LocalKeyValueStore {}

class _MockArDriveAuth extends Mock implements ArDriveAuth {}

class _FakeUser extends Fake implements User {}

void main() {
  late _MockLocalKeyValueStore store;
  late _MockArDriveAuth auth;
  late StreamController<User?> authController;

  setUp(() {
    store = _MockLocalKeyValueStore();
    auth = _MockArDriveAuth();
    authController = StreamController<User?>.broadcast();
    when(() => auth.onAuthStateChanged())
        .thenAnswer((_) => authController.stream);
  });

  tearDown(() {
    authController.close();
  });

  blocTest<AppBannerBloc, AppBannerState>(
    'emits visible when Android sunset banner has not been dismissed',
    build: () {
      when(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .thenReturn(false);
      return AppBannerBloc(keyValueStore: store, auth: auth);
    },
    act: (bloc) => bloc.add(
      const AppBannerRequested(banner: AppBannerType.androidSunset),
    ),
    expect: () => const <AppBannerState>[
      AppBannerVisible(banner: AppBannerType.androidSunset),
    ],
    verify: (_) {
      verify(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .called(1);
    },
  );

  blocTest<AppBannerBloc, AppBannerState>(
    'emits hidden when Android sunset banner already dismissed',
    build: () {
      when(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .thenReturn(true);
      return AppBannerBloc(keyValueStore: store, auth: auth);
    },
    act: (bloc) => bloc.add(
      const AppBannerRequested(banner: AppBannerType.androidSunset),
    ),
    expect: () => const <AppBannerState>[
      AppBannerHidden(),
    ],
    verify: (_) {
      verify(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .called(1);
    },
  );

  blocTest<AppBannerBloc, AppBannerState>(
    'persists dismissal and hides the banner',
    build: () {
      when(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .thenReturn(false);
      when(() => store.putBool(AppBannerType.androidSunset.storageKey, true))
          .thenAnswer((_) async => true);
      return AppBannerBloc(keyValueStore: store, auth: auth);
    },
    act: (bloc) async {
      bloc
        ..add(const AppBannerRequested(banner: AppBannerType.androidSunset))
        ..add(const AppBannerDismissed(banner: AppBannerType.androidSunset));
    },
    expect: () => const <AppBannerState>[
      AppBannerVisible(banner: AppBannerType.androidSunset),
      AppBannerHidden(),
    ],
    verify: (_) {
      verify(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .called(1);
      verify(() => store.putBool(AppBannerType.androidSunset.storageKey, true))
          .called(1);
    },
  );

  blocTest<AppBannerBloc, AppBannerState>(
    'resets dismissal when auth logs out',
    build: () {
      when(() => store.remove(AppBannerType.androidSunset.storageKey))
          .thenAnswer((_) async => true);
      when(() => store.getBool(AppBannerType.androidSunset.storageKey))
          .thenReturn(false);
      return AppBannerBloc(keyValueStore: store, auth: auth);
    },
    act: (bloc) async {
      authController.add(_FakeUser());
      await pumpEventQueue();
      authController.add(null);
    },
    expect: () => const <AppBannerState>[
      AppBannerVisible(banner: AppBannerType.androidSunset),
      AppBannerHidden(),
    ],
    verify: (_) {
      verify(() => store.remove(AppBannerType.androidSunset.storageKey))
          .called(1);
    },
  );
}
