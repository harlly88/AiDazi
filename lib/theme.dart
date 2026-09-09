import 'package:flutter/material.dart';
import 'app_theme.dart';

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: primaryBlue,
  colorScheme: ColorScheme.fromSeed(
    seedColor: primaryBlue,
    brightness: Brightness.light,
  ),
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xff333333),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xff333333),
  ),
);
