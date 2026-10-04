import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_colors.dart';
import 'package:qaq_app/src/config/app_themes.dart';
import 'package:qaq_app/src/navigation/app_navigator.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreferenceMode { auto, manual }

class AppProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _themePreferenceKey = "theme";
  static const String _themeModePreferenceKey = "theme_mode";

  static final AppProvider instance = AppProvider._();

  factory AppProvider() => instance;

  AppProvider._() {
    WidgetsBinding.instance.addObserver(this);
    checkTheme();
  }

  ThemeData _theme = _themeForBrightness(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  AppThemePreferenceMode get themePreferenceMode => _themePreferenceMode;
  AppThemePreferenceMode _themePreferenceMode = AppThemePreferenceMode.auto;

  bool get followsSystemTheme => _themePreferenceMode == AppThemePreferenceMode.auto;
  bool get isDarkTheme => _theme == AppThemes.darkTheme;

  ThemeMode get themeMode {
    if (followsSystemTheme) {
      return ThemeMode.system;
    }

    return isDarkTheme ? ThemeMode.dark : ThemeMode.light;
  }

  final Key? key = UniqueKey();
  final GlobalKey<NavigatorState> navigatorKey = AppNavigator.key;

  Future<void> setTheme(ThemeData value, String colorName) async {
    _theme = value;
    _themePreferenceMode = AppThemePreferenceMode.manual;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePreferenceKey, colorName);
    await prefs.setString(_themeModePreferenceKey, AppThemePreferenceMode.manual.name);

    _applySystemUiOverlayStyle(_theme);
    notifyListeners();
  }

  Future<void> setFollowSystemTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    if (value) {
      _themePreferenceMode = AppThemePreferenceMode.auto;
      _theme = _systemTheme;
      await prefs.setString(_themeModePreferenceKey, AppThemePreferenceMode.auto.name);
    } else {
      _themePreferenceMode = AppThemePreferenceMode.manual;

      final storedTheme = prefs.getString(_themePreferenceKey);
      if (storedTheme == null) {
        _theme = _systemTheme;
        await prefs.setString(_themePreferenceKey, isDarkTheme ? "dark" : "light");
      } else {
        _theme = storedTheme == "light" ? AppThemes.lightTheme : AppThemes.darkTheme;
      }

      await prefs.setString(_themeModePreferenceKey, AppThemePreferenceMode.manual.name);
    }

    _applySystemUiOverlayStyle(_theme);
    notifyListeners();
  }

  Future<ThemeData> checkTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final storedTheme = prefs.getString(_themePreferenceKey);
    final storedThemeMode = prefs.getString(_themeModePreferenceKey);

    if (storedThemeMode == null) {
      // Existing installs already have a saved light/dark preference. Keep it as
      // a manual choice; fresh installs default to following the system theme.
      _themePreferenceMode = storedTheme == null
          ? AppThemePreferenceMode.auto
          : AppThemePreferenceMode.manual;
      await prefs.setString(_themeModePreferenceKey, _themePreferenceMode.name);
    } else {
      _themePreferenceMode = storedThemeMode == AppThemePreferenceMode.manual.name
          ? AppThemePreferenceMode.manual
          : AppThemePreferenceMode.auto;
    }

    if (followsSystemTheme) {
      _theme = _systemTheme;
    } else {
      _theme = storedTheme == "light" ? AppThemes.lightTheme : AppThemes.darkTheme;
    }

    _applySystemUiOverlayStyle(_theme);
    notifyListeners();
    return _theme;
  }

  @override
  void didChangePlatformBrightness() {
    if (!followsSystemTheme) {
      return;
    }

    _theme = _systemTheme;
    _applySystemUiOverlayStyle(_theme);
    notifyListeners();
  }

  static ThemeData _themeForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? AppThemes.darkTheme : AppThemes.lightTheme;
  }

  ThemeData get _systemTheme => _themeForBrightness(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  void _applySystemUiOverlayStyle(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: isDark ? AppColors.darkPrimary : AppColors.mainColor,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }
}
