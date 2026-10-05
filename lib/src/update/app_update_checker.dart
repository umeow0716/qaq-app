import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qaq_app/src/config/app_link.dart';

class AppUpdateChecker {
  const AppUpdateChecker._();

  static Future<bool> isUpdateAvailable() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _parseVersion(packageInfo.version);
      if (currentVersion == null) return false;

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 6),
          followRedirects: false,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );

      try {
        final response = await dio.headUri<void>(AppLink.githubLatestReleaseUrl);
        final location = response.headers.value('location');
        if (location == null) return false;

        final latestVersion = _parseVersion(Uri.parse(location).pathSegments.last);
        if (latestVersion == null) return false;

        return _compareVersions(latestVersion, currentVersion) > 0;
      } finally {
        dio.close(force: true);
      }
    } catch (_) {
      return false;
    }
  }

  static List<int>? _parseVersion(String value) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) return null;

    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  static int _compareVersions(List<int> left, List<int> right) {
    for (var index = 0; index < 3; index++) {
      final difference = left[index].compareTo(right[index]);
      if (difference != 0) return difference;
    }
    return 0;
  }
}
