class AppLink {
  static const String githubOwnerName = "umeow0716";
  static const String repoName = "qaq-app";

  static const String githubRepoUrlString = "https://github.com/$githubOwnerName/$repoName";
  static const String privacyPolicyUrlString =
      'https://raw.githubusercontent.com/$githubOwnerName/$repoName/main/privacy-policy.md';

  static final Uri feedbackFormBaseUrl = Uri.parse(
    'https://docs.google.com/forms/d/e/1FAIpQLSfor78s8CDJNktaUefkwO40g0NDrkwrdxkqTokFERW0QP07eQ/viewform',
  );

  static Uri feedbackFormUrl({required String deviceModel, required String androidRelease}) => feedbackFormBaseUrl
      .replace(queryParameters: {'usp': 'pp_url', 'entry.931545544': '$deviceModel / Android $androidRelease'});
}
