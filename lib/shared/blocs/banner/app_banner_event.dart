part of 'app_banner_bloc.dart';

sealed class AppBannerEvent extends Equatable {
  const AppBannerEvent();

  @override
  List<Object> get props => [];
}

final class AppBannerRequested extends AppBannerEvent {
  const AppBannerRequested({required this.banner});

  final AppBannerType banner;

  @override
  List<Object> get props => [banner];
}

final class AppBannerDismissed extends AppBannerEvent {
  const AppBannerDismissed({required this.banner});

  final AppBannerType banner;

  @override
  List<Object> get props => [banner];
}

final class AppBannerReset extends AppBannerEvent {
  const AppBannerReset({required this.banner});

  final AppBannerType banner;

  @override
  List<Object> get props => [banner];
}
