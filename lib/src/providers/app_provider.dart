
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/config/app_colors.dart';
import 'package:flutter_app/src/config/app_themes.dart';
import 'package:flutter_app/src/navigation/app_navigator.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppProvider extends ChangeNotifier {
  static final AppProvider instance = AppProvider._();

  factory AppProvider() => instance;

  AppProvider._() {
    checkTheme();
  }

  ThemeData get theme => (() => _theme)();
  ThemeData _theme = Get.isDarkMode ? AppThemes.darkTheme : AppThemes.lightTheme;
  final Key? key = UniqueKey();
  final GlobalKey<NavigatorState> navigatorKey = AppNavigator.key;

  void setTheme(ThemeData value, String colorName) {
    _theme = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("theme", colorName).then((val) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: colorName == "dark" ? AppColors.darkPrimary : AppColors.mainColor,
          statusBarIconBrightness: colorName == "dark" ? Brightness.light : Brightness.dark,
        ));
      });
    });
    notifyListeners();
  }

  Future<ThemeData> checkTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString("theme") ?? "dark";

    if (r == "light") {
      setTheme(AppThemes.lightTheme, "light");
      return AppThemes.lightTheme;
    }

    setTheme(AppThemes.darkTheme, "dark");
    return AppThemes.darkTheme;
  }
}
