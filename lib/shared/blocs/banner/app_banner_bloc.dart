import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'app_banner_event.dart';
part 'app_banner_state.dart';

enum AppBannerType {
  announcement,
}

extension AppBannerTypeX on AppBannerType {
  String get storageKey {
    switch (this) {
      case AppBannerType.announcement:
        return 'app_announcement_banner_dismissed';
    }
  }
}

class AppBannerBloc extends Bloc<AppBannerEvent, AppBannerState> {
  AppBannerBloc({
    required LocalKeyValueStore keyValueStore,
    required ArDriveAuth auth,
  })  : _keyValueStore = keyValueStore,
        super(const AppBannerHidden()) {
    on<AppBannerRequested>(_onBannerRequested);
    on<AppBannerDismissed>(_onBannerDismissed);
    on<AppBannerReset>(_onBannerReset);

    _authSubscription = auth.onAuthStateChanged().listen((user) {
      if (user == null) {
        add(const AppBannerReset(banner: AppBannerType.announcement));
      } else {
        // Android sunset banner disabled - uncomment to re-enable:
        // add(const AppBannerRequested(banner: AppBannerType.announcement));
      }
    });
  }

  final LocalKeyValueStore _keyValueStore;
  StreamSubscription<User?>? _authSubscription;

  Future<void> _onBannerRequested(
    AppBannerRequested event,
    Emitter<AppBannerState> emit,
  ) async {
    switch (event.banner) {
      case AppBannerType.announcement:
        final dismissed =
            _keyValueStore.getBool(event.banner.storageKey) ?? false;
        if (!dismissed) {
          emit(AppBannerVisible(banner: event.banner));
        } else {
          emit(const AppBannerHidden());
        }
    }
  }

  Future<void> _onBannerDismissed(
    AppBannerDismissed event,
    Emitter<AppBannerState> emit,
  ) async {
    switch (event.banner) {
      case AppBannerType.announcement:
        await _keyValueStore.putBool(event.banner.storageKey, true);
        break;
    }

    emit(const AppBannerHidden());
  }

  Future<void> _onBannerReset(
    AppBannerReset event,
    Emitter<AppBannerState> emit,
  ) async {
    switch (event.banner) {
      case AppBannerType.announcement:
        await _keyValueStore.remove(event.banner.storageKey);
        break;
    }

    emit(const AppBannerHidden());
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
