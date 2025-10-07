part of 'app_banner_bloc.dart';

sealed class AppBannerState extends Equatable {
  const AppBannerState();

  @override
  List<Object> get props => [];
}

final class AppBannerVisible extends AppBannerState {
  const AppBannerVisible({required this.banner});

  final AppBannerType banner;

  @override
  List<Object> get props => [banner];
}

final class AppBannerHidden extends AppBannerState {
  const AppBannerHidden();
}
