import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

final ThemeData materialTheme = ThemeData(
  scaffoldBackgroundColor: const Color.fromARGB(255, 22, 22, 24),
  useMaterial3: false,
  colorScheme: const ColorScheme(
    brightness: Brightness.dark,
    primary: Color.fromARGB(255, 54, 53, 59),
    onPrimary: Colors.white,
    secondary: Colors.green,
    onSecondary: Colors.white,
    error: Colors.red,
    onError: Colors.black,
    surface: Color.fromARGB(255, 22, 22, 24),
    onSurface: Colors.white,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      foregroundColor: const Color.fromARGB(255, 54, 53, 59), // Text color
      backgroundColor: Colors.green, // Background color
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    ),
  ),
  secondaryHeaderColor: Colors.black,
);

const CupertinoThemeData cupertinoTheme = CupertinoThemeData(
  brightness: Brightness.dark,
  primaryColor: Color.fromARGB(255, 119, 242, 161),
  primaryContrastingColor: Color.fromARGB(255, 54, 53, 59),
  barBackgroundColor: Color.fromARGB(255, 22, 22, 24),
  scaffoldBackgroundColor: Color.fromARGB(255, 22, 22, 24),
  textTheme: CupertinoTextThemeData(
    primaryColor: Colors.white,
  ),
);
