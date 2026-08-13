import 'package:flutter/material.dart';

import '../screens/chord_matrix_screen.dart';
import '../screens/pitch_spectrogram_screen.dart';
import '../screens/strobe_tuner_screen.dart';
import '../screens/tuner_screen.dart';

/// Side drawer (hamburger menu) listing every screen in the app.
/// Inserted as the `Scaffold.drawer` on each screen so the same menu
/// is reachable no matter which screen the user is currently on.
class AppDrawer extends StatelessWidget {
  /// Which screen is currently showing, so its row can be highlighted
  /// and made non-tappable (no point navigating to where you are).
  final AppScreen current;

  const AppDrawer({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D1A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.graphic_eq_rounded,
              label: 'Tuner',
              subtitle: 'Arc gauge + note display',
              screen: AppScreen.tuner,
              current: current,
              builder: (_) => const TunerScreen(),
            ),
            _DrawerItem(
              icon: Icons.ssid_chart_rounded,
              label: 'Pitch spectrogram',
              subtitle: 'Scrolling pitch history',
              screen: AppScreen.spectrogram,
              current: current,
              builder: (_) => const PitchSpectrogramScreen(),
            ),
            _DrawerItem(
              icon: Icons.waves_rounded,
              label: 'Strobe tuner',
              subtitle: 'Waveform + strobe display',
              screen: AppScreen.strobe,
              current: current,
              builder: (_) => const StrobeTunerScreen(),
            ),
            _DrawerItem(
              icon: Icons.grid_on_rounded,
              label: 'Chord matrix',
              subtitle: 'Live chord detection grid',
              screen: AppScreen.chordMatrix,
              current: current,
              builder: (_) => const ChordMatrixScreen(),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Swipe from the edge or tap the menu icon to switch screens.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum AppScreen { tuner, spectrogram, strobe, chordMatrix }

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
            ),
            child: const Icon(Icons.music_note_rounded, color: Color(0xFF00E676), size: 24),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guitar Tuner',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                'Pro tuning suite',
                style: TextStyle(color: Color(0xFF6B6B9A), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final AppScreen screen;
  final AppScreen current;
  final WidgetBuilder builder;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.screen,
    required this.current,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final bool isActive = screen == current;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isActive
            ? null
            : () {
                Navigator.of(context).pop(); // close drawer
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => Builder(builder: builder),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 200),
                  ),
                );
              },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF00E676).withOpacity(0.12) : null,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: const Color(0xFF00E676).withOpacity(0.35))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isActive ? const Color(0xFF00E676) : Colors.white60,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isActive ? const Color(0xFF00E676) : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF6B6B9A), fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (isActive)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
