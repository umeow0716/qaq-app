import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:flutter_app/src/version/update/app_update.dart';

class APPVersion {
  static void initAndCheck() async {
    await updateLocalVersion();
  }

  static Future<void> updateLocalVersion() async {
    final current = await AppUpdate.getAppVersion();
    final previous = LocalStorage.instance.getVersion();
    Log.d("Previous: $previous\nCurrent: $current");

    if (previous != current) {
      await LocalStorage.instance.setVersion(current);
    }
  }
}
