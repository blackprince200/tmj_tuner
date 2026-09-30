import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guitar_tuner_app/app/routes/app_router.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Force portrait — tuners are always portrait apps.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Dark status bar to match the dark theme.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const GuitarTunerApp());
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
        title: 'TMJ Guitar Tuner',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        routerConfig: AppRouter.router,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: const Color(0xFF0E0E1A),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2BBE8C),
        brightness: brightness,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Color(0xFF2BBE8C),
        thumbColor: Color(0xFF2BBE8C),
      ),
    );
  }
}
