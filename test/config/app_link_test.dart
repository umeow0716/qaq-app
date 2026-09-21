import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/config/app_link.dart';

void main() {
  test('feedback form URL pre-fills Android device information', () {
    final uri = AppLink.feedbackFormUrl(deviceModel: 'Pixel 8', androidRelease: '16');

    expect(uri.queryParameters['usp'], 'pp_url');
    expect(uri.queryParameters['entry.931545544'], 'Pixel 8 / Android 16');
  });
}
