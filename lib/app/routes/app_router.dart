import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:guitar_tuner_app/app/routes/routes_name.dart';
import 'package:guitar_tuner_app/app/routes/routes_pages.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: RoutesName.splash,

    routes: RoutePages.routes,

    errorBuilder: (context, state){
      return Scaffold(
        appBar: AppBar(
          title: const Text("Navigation Error"),
        ),
        body: const Text("data"),
      );
    }
  );
}