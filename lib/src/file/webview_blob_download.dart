import 'dart:convert';

const String webViewBlobDownloadJavaScriptChannel = 'QAQBlobDownload';


/// Installs a lightweight page-side filename tracker for WebView downloads.
///
/// Sites that create `blob:` URLs often set the real filename on an
/// `<a download="...">` element. Native download callbacks may only receive the
/// opaque blob UUID, so remember the anchor's filename synchronously before the
/// browser starts the download.
String buildWebViewDownloadFilenameCaptureScript() => r'''
(() => {
  if (window.__qaqDownloadFilenameCaptureInstalled) return;
  window.__qaqDownloadFilenameCaptureInstalled = true;
  window.__qaqDownloadFilenameHints ??= Object.create(null);

  const remember = (anchor) => {
    try {
      if (!(anchor instanceof HTMLAnchorElement)) return;
      const href = String(anchor.href || '').trim();
      const filename = String(anchor.getAttribute('download') || '').trim();
      if (!href || !filename) return;
      window.__qaqDownloadFilenameHints[href] = filename;
    } catch (_) {}
  };

  const originalClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function(...args) {
    remember(this);
    return originalClick.apply(this, args);
  };

  document.addEventListener('click', (event) => {
    let target = event.target;
    if (target && target.nodeType === Node.TEXT_NODE) target = target.parentElement;
    const anchor = target && target.closest ? target.closest('a[download]') : null;
    if (anchor) remember(anchor);
  }, true);
})();
''';

/// Looks up the filename captured for [downloadUrl] in the current page.
String buildWebViewDownloadFilenameLookupScript(String downloadUrl) {
  final encodedUrl = jsonEncode(downloadUrl);
  return '''
(() => {
  const value = window.__qaqDownloadFilenameHints?.[$encodedUrl];
  return typeof value === 'string' ? value : '';
})()
''';
}

/// Normalizes JavaScript return values from the different WebView backends.
String? parseWebViewDownloadFilenameLookupResult(Object? result) {
  if (result == null) return null;
  var value = '$result'.trim();
  if (value.isEmpty || value == 'null' || value == 'undefined') return null;

  try {
    final decoded = jsonDecode(value);
    if (decoded is String) value = decoded.trim();
  } on FormatException {
    // Some backends already return the unquoted string.
  }

  return value.isEmpty ? null : value;
}

/// Builds JavaScript that copies a page-owned blob URL to Flutter in bounded
/// base64 chunks. The blob is read inside the document that created it because
/// blob: URLs cannot be downloaded by an external HTTP client.
String buildWebViewBlobDownloadScript({
  required String requestId,
  required String blobUrl,
}) {
  final encodedRequestId = jsonEncode(requestId);
  final encodedBlobUrl = jsonEncode(blobUrl);

  return '''
(() => {
  const requestId = $encodedRequestId;
  const blobUrl = $encodedBlobUrl;
  const matchingAnchor = Array.from(document.querySelectorAll('a[download]'))
    .reverse()
    .find((anchor) => anchor.href === blobUrl);
  const filenameHint = String(
    window.__qaqDownloadFilenameHints?.[blobUrl] ||
    matchingAnchor?.getAttribute('download') ||
    '',
  ).trim();
  const channel = window.$webViewBlobDownloadJavaScriptChannel;
  const send = (payload) => {
    if (!channel || typeof channel.postMessage !== 'function') return;
    channel.postMessage(JSON.stringify({requestId, ...payload}));
  };

  const encodeChunk = (bytes) => {
    let binary = '';
    const step = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += step) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + step));
    }
    return btoa(binary);
  };

  (async () => {
    try {
      if (!channel || typeof channel.postMessage !== 'function') {
        throw new Error('QAQ blob download channel is unavailable');
      }

      const response = await fetch(blobUrl);
      const blob = await response.blob();
      const total = blob.size;
      send({
        type: 'start',
        total,
        mimeType: blob.type || '',
        filenameHint,
      });

      let received = 0;
      if (blob.stream) {
        const reader = blob.stream().getReader();
        while (true) {
          const value = await reader.read();
          if (value.done) break;
          const bytes = value.value;
          for (let offset = 0; offset < bytes.length; offset += 256 * 1024) {
            const part = bytes.subarray(offset, offset + 256 * 1024);
            received += part.length;
            send({
              type: 'chunk',
              data: encodeChunk(part),
              received,
              total,
            });
          }
        }
      } else {
        const bytes = new Uint8Array(await blob.arrayBuffer());
        for (let offset = 0; offset < bytes.length; offset += 256 * 1024) {
          const part = bytes.subarray(offset, offset + 256 * 1024);
          received += part.length;
          send({
            type: 'chunk',
            data: encodeChunk(part),
            received,
            total,
          });
        }
      }

      send({type: 'done', received, total});
    } catch (error) {
      send({
        type: 'error',
        message: String(error && (error.stack || error.message) || error),
      });
    }
  })();
})();
''';
}

Map<String, Object?>? decodeWebViewBlobDownloadMessage(String message) {
  try {
    final decoded = jsonDecode(message);
    if (decoded is! Map) return null;
    return decoded.map<String, Object?>((key, value) => MapEntry('$key', value));
  } on FormatException {
    return null;
  }
}
