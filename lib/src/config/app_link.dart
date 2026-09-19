import 'dart:io';

class AppLink {
  static const String androidAppPackageName = "dev.umeow.tat_umeow";
  static const String _playStoreUrl = "https://play.google.com/store/apps/details?id=$androidAppPackageName";
  static const String _appleStoreUrl = "https://apps.apple.com/tw/app/id1513875597";

  static const String githubOwnerName = "NEO-TAT";
  static const String tatRepoName = "tat_flutter";

  static const String tatGitHubRepoUrlString = "https://github.com/$githubOwnerName/$tatRepoName";
  static const String privacyPolicyUrlString =
      'https://raw.githubusercontent.com/$githubOwnerName/$tatRepoName/dev/privacy-policy.md';

  static String get storeUrlString => (Platform.isAndroid) ? _playStoreUrl : _appleStoreUrl;
}
