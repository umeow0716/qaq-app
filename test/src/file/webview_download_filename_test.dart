import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/file/webview_download_filename.dart';

void main() {
  group('sanitizeWebViewDownloadFilename', () {
    test('removes wrapping quotes', () {
      expect(sanitizeWebViewDownloadFilename("'book.pdf'"), 'book.pdf');
      expect(sanitizeWebViewDownloadFilename('"book.pdf"'), 'book.pdf');
      expect(sanitizeWebViewDownloadFilename('“book.pdf”'), 'book.pdf');
    });

    test('decodes encoded wrapping quotes', () {
      expect(sanitizeWebViewDownloadFilename('%27book.pdf%27'), 'book.pdf');
    });

    test('replaces cross-platform unsafe characters', () {
      expect(sanitizeWebViewDownloadFilename(r'report:2026/10\04?.pdf'), 'report_2026_10_04_.pdf');
    });

    test('preserves an apostrophe inside a normal filename', () {
      expect(sanitizeWebViewDownloadFilename("teacher's-notes.pdf"), "teacher's-notes.pdf");
    });

    test('avoids Windows reserved device names', () {
      expect(sanitizeWebViewDownloadFilename('CON.txt'), '_CON.txt');
      expect(sanitizeWebViewDownloadFilename('lpt1.log'), '_lpt1.log');
    });

    test('falls back when nothing usable remains', () {
      expect(sanitizeWebViewDownloadFilename(' .. '), 'download');
    });
  });
}
