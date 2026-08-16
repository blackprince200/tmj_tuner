import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'presentation/bloc/tuner_cubit.dart';
import 'presentation/screens/tuner_screen.dart';
import 'presentation/theme/app_colors.dart';
import 'services/audio_capture_service.dart';

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
    return BlocProvider(
      create: (_) => TunerCubit(
        audioService: RecordAudioCaptureService(),
      ),
      child: MaterialApp(
        title: 'TMJ Guitar Tuner',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const TunerScreen(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.baseBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryAccent,
        brightness: brightness,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primaryAccent,
        thumbColor: AppColors.primaryAccent,
      ),
    );
  }
}
