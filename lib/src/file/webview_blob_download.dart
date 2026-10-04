import 'dart:convert';

const String webViewBlobDownloadJavaScriptChannel = 'QAQBlobDownload';

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
      send({type: 'start', total, mimeType: blob.type || ''});

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
