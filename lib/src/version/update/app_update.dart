// ignore_for_file: import_of_legacy_library_into_null_safe

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  static Future<bool> checkUpdate() async => false;

  static Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }
}
