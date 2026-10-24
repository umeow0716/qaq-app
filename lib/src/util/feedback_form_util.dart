import 'package:flutter/services.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:qaq_app/src/config/app_link.dart';

class FeedbackFormUtil {
  static const _platform = MethodChannel(AppConfig.methodChannelName);

  static Future<Uri> buildUrl() async {
    try {
      final deviceInfo = await _platform.invokeMapMethod<String, dynamic>('get_feedback_device_info');
      final model = deviceInfo?['model']?.toString().trim();
      final androidRelease = deviceInfo?['androidRelease']?.toString().trim();
      if (model != null && model.isNotEmpty && androidRelease != null && androidRelease.isNotEmpty) {
        return AppLink.feedbackFormUrl(deviceModel: model, androidRelease: androidRelease);
      }
    } on PlatformException catch (error, stackTrace) {
      Log.eWithStack(error, stackTrace);
    } on MissingPluginException catch (error, stackTrace) {
      Log.eWithStack(error, stackTrace);
    }
    return AppLink.feedbackFormBaseUrl;
  }
}
