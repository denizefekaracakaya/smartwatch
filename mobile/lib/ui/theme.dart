import 'package:flutter/material.dart';

/// Palette: near-black surfaces, warm off-white text and a single amber accent. Covers use the muted
/// earth tones in [coverColors] so a list of songs reads like a shelf of records, not a rainbow.
class AppColors {
  static const background = Color(0xFF0F0F10);
  static const surface = Color(0xFF17171A);
  static const surfaceHigh = Color(0xFF212125);
  static const outline = Color(0xFF2C2C31);
  static const text = Color(0xFFEDEBE7);
  static const textMuted = Color(0xFF9B9A9F);
  static const accent = Color(0xFFE8A33D);
  static const onAccent = Color(0xFF1C1407);
  static const error = Color(0xFFE5675A);

  static const coverColors = [
    Color(0xFF8E4B3B), // terracotta
    Color(0xFF3F6B6E), // teal
    Color(0xFF5D5A8C), // dusty indigo
    Color(0xFF9A7B3F), // ochre
    Color(0xFF4B6648), // olive
    Color(0xFF7C4E63), // plum
    Color(0xFF3E5672), // slate blue
    Color(0xFF6E6259), // taupe
  ];
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    surface: AppColors.background,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHigh,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
    error: AppColors.error,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  final text = base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.accent)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted,
          )),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: AppColors.text,
      inactiveTrackColor: AppColors.outline,
      thumbColor: AppColors.text,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      iconColor: AppColors.textMuted,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
    popupMenuTheme: const PopupMenuThemeData(color: AppColors.surfaceHigh),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
  );
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// "12 şarkı · 54 dk"
String summarize(int count, Duration total, {String unit = 'şarkı'}) {
  final minutes = total.inMinutes;
  final length = minutes >= 60 ? '${minutes ~/ 60} sa ${minutes % 60} dk' : '$minutes dk';
  return count == 0 ? 'Boş' : '$count $unit · $length';
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
