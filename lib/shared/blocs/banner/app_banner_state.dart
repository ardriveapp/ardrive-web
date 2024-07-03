part of 'app_banner_bloc.dart';

sealed class AppBannerState extends Equatable {
  const AppBannerState();

  @override
  List<Object> get props => [];
}

final class AppBannerVisible extends AppBannerState {}

final class AppBannerHidden extends AppBannerState {}
