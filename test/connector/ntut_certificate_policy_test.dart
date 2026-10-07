import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/ntut_certificate_policy.dart';

void main() {
  group('NtutCertificatePolicy', () {
    test('trusts only ntut.edu.tw and its subdomains', () {
      expect(NtutCertificatePolicy.trustsHost('ntut.edu.tw'), isTrue);
      expect(NtutCertificatePolicy.trustsHost('NPORTAL.NTUT.EDU.TW'), isTrue);
      expect(NtutCertificatePolicy.trustsHost('foo.bar.ntut.edu.tw'), isTrue);

      expect(NtutCertificatePolicy.trustsHost('localhost'), isFalse);
      expect(NtutCertificatePolicy.trustsHost('127.0.0.1'), isFalse);
      expect(NtutCertificatePolicy.trustsHost('evilntut.edu.tw'), isFalse);
      expect(NtutCertificatePolicy.trustsHost('ntut.edu.tw.example.com'), isFalse);
    });

    test('extracts the Windows WebView SSL request URI', () {
      final uri = NtutCertificatePolicy.webViewRequestUri(
        'SSL certificate error for https://nportal.ntut.edu.tw/login?next=a:b: '
        'WebErrorStatusCertificateIsInvalid.',
      );

      expect(uri, Uri.parse('https://nportal.ntut.edu.tw/login?next=a:b'));
      expect(NtutCertificatePolicy.webViewRequestUri('unexpected format'), isNull);
    });

    test('allows only invalid-chain Windows WebView errors for NTUT hosts', () {
      expect(
        NtutCertificatePolicy.allowsWindowsWebViewCertificateError(
          'SSL certificate error for https://nportal.ntut.edu.tw/login.do: '
          'WebErrorStatusCertificateIsInvalid.',
        ),
        isTrue,
      );
      expect(
        NtutCertificatePolicy.allowsWindowsWebViewCertificateError(
          'SSL certificate error for https://nportal.ntut.edu.tw/login.do: '
          'WebErrorStatusCertificateExpired.',
        ),
        isFalse,
      );
      expect(
        NtutCertificatePolicy.allowsWindowsWebViewCertificateError(
          'SSL certificate error for https://example.com/: '
          'WebErrorStatusCertificateIsInvalid.',
        ),
        isFalse,
      );
    });
  });
}
