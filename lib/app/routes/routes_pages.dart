import 'package:go_router/go_router.dart';
import 'package:guitar_tuner_app/app/routes/routes_name.dart';

import 'package:guitar_tuner_app/pages/splash.dart';


class RoutePages {
  RoutePages._();

  static List<RouteBase> routes = [
    GoRoute(
      path: RoutesName.splash,
      builder: (context, state){
        return const SplashPage();
      },
    )
  ];
}