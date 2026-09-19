import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/ui/pages/coursedetail/course_detail_page.dart';
import 'package:qaq_app/ui/pages/coursedetail/screen/ischoolplus/iplus_announcement_detail_page.dart';
import 'package:qaq_app/ui/pages/fileviewer/file_viewer_page.dart';
import 'package:qaq_app/ui/pages/logconsole/log_console.dart';
import 'package:qaq_app/ui/pages/other/page/about_page.dart';
import 'package:qaq_app/ui/pages/other/page/contributors_page.dart';
import 'package:qaq_app/ui/pages/other/page/dev_page.dart';
import 'package:qaq_app/ui/pages/other/page/privacy_policy_page.dart';
import 'package:qaq_app/ui/pages/other/page/setting_page.dart';
import 'package:qaq_app/ui/pages/other/page/sub_system_page.dart';
import 'package:qaq_app/ui/pages/videoplayer/class_video_player.dart';
import 'package:qaq_app/ui/pages/webview/web_view_page.dart';
import 'package:qaq_app/ui/screen/login_screen.dart';
import 'package:qaq_app/ui/screen/main_screen.dart';
import 'package:get/get.dart';

class RouteUtils {
  static Transition transition = (Platform.isAndroid) ? Transition.downToUp : Transition.cupertino;

  static Future<dynamic> toLoginScreen() async {
    return await Get.off(() => const LoginScreen(), transition: transition);
  }

  static Future<dynamic> launchMainPage() async => await Get.offAll(() => const MainScreen(), transition: transition);

  static Future<dynamic> toDevPage() async {
    return await Get.to(() => const DevPage(), transition: transition);
  }

  static Future<dynamic> toSubSystemPage(String title, String? arg) async {
    return await Get.to(
      () => SubSystemPage(title: title, arg: arg),
      transition: transition,
      preventDuplicates: false,
    );
  }

  static Future<dynamic> toFileViewerPage(String title, String path) async {
    return await Get.to(
      () => FileViewerPage(title: title, path: path),
      transition: transition,
    );
  }

  static Future<dynamic> toISchoolPage(String studentId, CourseInfoJson courseInfo) async {
    return await Get.to(() => ISchoolPage(studentId, courseInfo), transition: transition);
  }

  static Future<dynamic> toPrivacyPolicyPage() async {
    return await Get.to(() => const PrivacyPolicyPage(), transition: transition);
  }

  static Future<dynamic> toContributorsPage() async {
    return await Get.to(() => ContributorsPage(), transition: transition);
  }

  static Future<dynamic> toAboutPage() async {
    return await Get.to(() => const AboutPage(), transition: transition);
  }

  static Future<dynamic> toSettingPage(PageController controller) async =>
      await Get.to(() => SettingPage(controller), transition: transition);

  static Future<void> toWebViewPage({required Uri initialUrl, String? title, bool shouldUseAppCookies = false}) =>
      WebViewPage.instance(initialUrl: initialUrl, title: title, shouldUseAppCookies: shouldUseAppCookies);

  static Future<dynamic> toLogConsolePage() async {
    return await Get.to(() => LogConsole(dark: true), transition: transition);
  }

  static Future<dynamic> toIPlusAnnouncementDetailPage(CourseInfoJson courseInfo, Map<String, dynamic> detail) async {
    return await Get.to(() => IPlusAnnouncementDetailPage(courseInfo, detail), transition: transition);
  }

  static Future<dynamic> toVideoPlayer(String url, CourseInfoJson courseInfo, String name) async =>
      await Get.to(() => ClassVideoPlayer(url, courseInfo, name), transition: transition);
}
