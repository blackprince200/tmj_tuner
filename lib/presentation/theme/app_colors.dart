import 'package:flutter/material.dart';

/// Centralized color registry for the app theme.
/// Replaces direct inline hexadecimal definitions to ensure cohesive look and feel.
class AppColors {
  AppColors._();

  // Core Theme Colors
  static const Color baseBackground = Color(0xFF0B0F14); // Near-black, cool undertone
  static const Color surfaceCard = Color(0xFF141B23);     // Surface panel background
  static const Color headerNavBar = Color(0xFF0B5BA4);    // Accent blue for headers
  static const Color primaryAccent = Color(0xFFFFAA00);   // Brand orange: active states, CTAs, icons
  static const Color secondaryAccent = Color(0xFF3B8FD6); // Brightened blue for highlights/links
  static const Color textPrimary = Color(0xFFF5F5F5);     // Off-white for high legibility
  static const Color textSecondary = Color(0xFF9AA5B1);   // Muted gray for captions/subtitles
  static const Color dividersBorders = Color(0xFF1E2833); // Divider lines and element borders

  // Tuner Status & Accuracy Colors
  static const Color tuningGreen = Color(0xFF32CD32);     // In tune
  static const Color tuningYellow = Color(0xFFFFD700);    // Slightly flat/sharp
  static const Color tuningOrange = Color(0xFFFFAA00);    // Moderately flat/sharp
  static const Color tuningRed = Color(0xFFFF4B6E);       // Significantly flat/sharp
  static const Color tuningInactive = Color(0xFF444444);  // Neutral/inactive states
}
