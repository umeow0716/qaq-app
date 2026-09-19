import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:path_provider/path_provider.dart';

class UserSessionArtifacts {
  const UserSessionArtifacts._();

  static const _platform = MethodChannel(AppConfig.methodChannelName);

  static Future<void> clear() async {
    final supportDir = await getApplicationSupportDirectory();
    final courseWidget = File('${supportDir.path}/course_widget.png');
    if (await courseWidget.exists()) {
      await courseWidget.delete();
    }

    if (Platform.isAndroid) {
      try {
        await _platform.invokeMethod<void>('update_home_screen_weight');
      } on MissingPluginException {
        // Tests or unsupported runtimes may not register the Android channel.
      }
    }
  }
}
