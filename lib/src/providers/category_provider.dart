import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CategoryProvider extends ChangeNotifier {
  CategoryProvider() {
    getHidden();
    getSort();
  }

  bool showHidden = false;
  int sort = 0;

  Future<void> setHidden(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool("hidden", value);
    showHidden = value;
    notifyListeners();
  }

  Future<void> getHidden() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool h = prefs.getBool("hidden") ?? false;
    setHidden(h);
  }

  Future<void> setSort(int value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt("sort", value);
    sort = value;
    notifyListeners();
  }

  Future<void> getSort() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int h = prefs.getInt("sort") ?? 0;
    setSort(h);
  }
}
