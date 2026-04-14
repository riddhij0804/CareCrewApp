import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF103A86),
      brightness: Brightness.light,
      primary: const Color(0xFF103A86),
      secondary: const Color(0xFFFFC94D),
      tertiary: const Color(0xFF8CC8FF),
      surface: Colors.white,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFCFE9FB),
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.manrope(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0F2D66),
          letterSpacing: -0.6,
        ),
        headlineLarge: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0F2D66),
        ),
        headlineMedium: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0F2D66),
        ),
        titleLarge: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0F2D66),
        ),
        titleMedium: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F2D66),
        ),
        bodyLarge: GoogleFonts.manrope(color: const Color(0xFF1F3B6B)),
        bodyMedium: GoogleFonts.manrope(color: const Color(0xFF1F3B6B)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFCFE9FB),
        foregroundColor: Color(0xFF0F2D66),
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEAF4FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF103A86), width: 1.3),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF103A86),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          minimumSize: const Size.fromHeight(52),
          elevation: 4,
          shadowColor: const Color(0xFF103A86),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFEAF4FB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F2D66),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        height: 72,
        indicatorColor: const Color(0xFF103A86),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? Colors.white : const Color(0xFF7C90AF),
          ),
        ),
      ),
    );
  }
}
