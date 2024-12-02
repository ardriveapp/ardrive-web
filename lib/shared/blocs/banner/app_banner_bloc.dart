import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'app_banner_event.dart';
part 'app_banner_state.dart';

class AppBannerBloc extends Bloc<AppBannerEvent, AppBannerState> {
  AppBannerBloc() : super(AppBannerHidden()) {
    on<AppBannerEvent>((event, emit) {
      if (event is AppBannerCloseEvent) {
        emit(AppBannerHidden());
      }
    });
  }
}
