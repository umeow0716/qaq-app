import 'dart:convert';

const String webViewBlobDownloadJavaScriptChannel = 'QAQBlobDownload';

/// Installs a lightweight page-side filename tracker for WebView downloads.
///
/// Sites that create `blob:` URLs often set the real filename on an
/// `<a download="...">` element. Native download callbacks may only receive the
/// opaque blob UUID, so remember the anchor's filename synchronously before the
/// browser starts the download. Same-origin child frames are instrumented too,
/// because document viewers commonly create their blob download inside an
/// iframe rather than the top-level document.
String buildWebViewDownloadFilenameCaptureScript() => r'''
(() => {
  const install = (targetWindow) => {
    try {
      if (!targetWindow || !targetWindow.document) return;
      if (targetWindow.__qaqDownloadFilenameCaptureInstalled) return;
      targetWindow.__qaqDownloadFilenameCaptureInstalled = true;
      targetWindow.__qaqDownloadFilenameHints ??= Object.create(null);

      const remember = (anchor) => {
        try {
          const Anchor = targetWindow.HTMLAnchorElement;
          if (!Anchor || !(anchor instanceof Anchor)) return;
          const href = String(anchor.href || '').trim();
          const filename = String(anchor.getAttribute('download') || '').trim();
          if (!href || !filename) return;
          targetWindow.__qaqDownloadFilenameHints[href] = filename;
        } catch (_) {}
      };

      const Anchor = targetWindow.HTMLAnchorElement;
      const originalClick = Anchor?.prototype?.click;
      if (typeof originalClick === 'function') {
        Anchor.prototype.click = function(...args) {
          remember(this);
          return originalClick.apply(this, args);
        };
      }

      targetWindow.document.addEventListener('click', (event) => {
        try {
          let target = event.target;
          if (target && target.nodeType === targetWindow.Node.TEXT_NODE) {
            target = target.parentElement;
          }
          const anchor = target && target.closest
            ? target.closest('a[download]')
            : null;
          if (anchor) remember(anchor);
        } catch (_) {}
      }, true);

      const installFrame = (frame) => {
        try {
          if (frame.contentWindow) install(frame.contentWindow);
        } catch (_) {}
        try {
          frame.addEventListener('load', () => {
            try {
              if (frame.contentWindow) install(frame.contentWindow);
            } catch (_) {}
          });
        } catch (_) {}
      };

      const scanFrames = (root) => {
        try {
          if (root.matches?.('iframe,frame')) installFrame(root);
          root.querySelectorAll?.('iframe,frame').forEach(installFrame);
        } catch (_) {}
      };

      scanFrames(targetWindow.document);
      const Observer = targetWindow.MutationObserver;
      if (Observer) {
        const observer = new Observer((records) => {
          for (const record of records) {
            for (const node of record.addedNodes || []) {
              if (node && node.nodeType === targetWindow.Node.ELEMENT_NODE) {
                scanFrames(node);
              }
            }
          }
        });
        observer.observe(
          targetWindow.document.documentElement || targetWindow.document,
          {childList: true, subtree: true},
        );
      }
    } catch (_) {}
  };

  install(window);
})();
''';

/// Looks up the filename captured for [downloadUrl] in the current page and
/// every same-origin child frame.
String buildWebViewDownloadFilenameLookupScript(String downloadUrl) {
  final encodedUrl = jsonEncode(downloadUrl);
  return '''
(() => {
  const downloadUrl = $encodedUrl;
  const visited = new Set();

  const lookup = (targetWindow) => {
    try {
      if (!targetWindow || visited.has(targetWindow)) return '';
      visited.add(targetWindow);

      const remembered = targetWindow.__qaqDownloadFilenameHints?.[downloadUrl];
      if (typeof remembered === 'string' && remembered.trim()) {
        return remembered.trim();
      }

      const anchors = Array.from(
        targetWindow.document?.querySelectorAll?.('a[download]') || [],
      ).reverse();
      const matchingAnchor = anchors.find(
        (anchor) => String(anchor.href || '') === downloadUrl,
      );
      const filename = matchingAnchor?.getAttribute('download');
      if (typeof filename === 'string' && filename.trim()) {
        return filename.trim();
      }

      const frames = targetWindow.document?.querySelectorAll?.('iframe,frame') || [];
      for (const frame of frames) {
        try {
          const value = lookup(frame.contentWindow);
          if (value) return value;
        } catch (_) {}
      }
    } catch (_) {}
    return '';
  };

  return lookup(window);
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
  const visited = new Set();
  const lookupFilenameHint = (targetWindow) => {
    try {
      if (!targetWindow || visited.has(targetWindow)) return '';
      visited.add(targetWindow);

      const remembered = targetWindow.__qaqDownloadFilenameHints?.[blobUrl];
      if (typeof remembered === 'string' && remembered.trim()) {
        return remembered.trim();
      }

      const anchors = Array.from(
        targetWindow.document?.querySelectorAll?.('a[download]') || [],
      ).reverse();
      const matchingAnchor = anchors.find(
        (anchor) => String(anchor.href || '') === blobUrl,
      );
      const filename = matchingAnchor?.getAttribute('download');
      if (typeof filename === 'string' && filename.trim()) {
        return filename.trim();
      }

      const frames = targetWindow.document?.querySelectorAll?.('iframe,frame') || [];
      for (const frame of frames) {
        try {
          const value = lookupFilenameHint(frame.contentWindow);
          if (value) return value;
        } catch (_) {}
      }
    } catch (_) {}
    return '';
  };
  const filenameHint = lookupFilenameHint(window);
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
