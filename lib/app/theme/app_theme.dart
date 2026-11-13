import 'package:flutter/material.dart';

abstract final class AppTheme {
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF386A5E),
    ),
    scaffoldBackgroundColor: const Color(0xFFF6F8F5),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF6F8F5),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
    ),
  );
}
