import 'package:flutter/material.dart';

import 'color_schemes.g.dart';

class AppThemes {
  static final lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'TATFont',
    colorScheme: lightColorScheme,
    appBarTheme: AppBarThemeData(
      backgroundColor: lightColorScheme.primary,
      foregroundColor: lightColorScheme.onPrimary,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: lightColorScheme.surface,
      selectedItemColor: lightColorScheme.tertiary,
      selectedIconTheme: IconThemeData(color: lightColorScheme.tertiary),
      unselectedItemColor: lightColorScheme.onSurface,
      unselectedIconTheme: IconThemeData(color: lightColorScheme.onSurface),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: lightColorScheme.tertiaryContainer,
      unselectedLabelColor: lightColorScheme.onPrimary,
    ),
  );

  static final darkTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'TATFont',
    colorScheme: darkColorScheme,
    appBarTheme: AppBarThemeData(
      backgroundColor: darkColorScheme.primaryContainer,
      foregroundColor: darkColorScheme.onPrimaryContainer,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: darkColorScheme.surface,
      selectedItemColor: darkColorScheme.tertiary,
      selectedIconTheme: IconThemeData(color: darkColorScheme.tertiary),
      unselectedItemColor: darkColorScheme.onSurface,
      unselectedIconTheme: IconThemeData(color: darkColorScheme.onSurface),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: darkColorScheme.tertiary,
      unselectedLabelColor: darkColorScheme.onPrimaryContainer,
    ),
  );
}
