part of 'app_banner_bloc.dart';

sealed class AppBannerEvent extends Equatable {
  const AppBannerEvent();

  @override
  List<Object> get props => [];
}

final class AppBannerCloseEvent extends AppBannerEvent {
  const AppBannerCloseEvent();
}
