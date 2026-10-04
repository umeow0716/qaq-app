/// Normalizes a WebView download filename so it is safe on every filesystem
/// currently supported by QAQ's custom download flows.
String sanitizeWebViewDownloadFilename(
  String value, {
  String fallback = 'download',
}) {
  var result = _decodeFilename(value).trim();
  result = _stripWrappingQuotes(result);

  // Use the strict Windows-invalid set as the common denominator. Linux and
  // Android allow more of these characters, but normalizing them here keeps a
  // filename portable when downloads are moved between devices.
  result = result.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), '_');
  result = result.trim().replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  result = _stripWrappingQuotes(result.trim());
  result = result.replaceAll(RegExp(r'[. ]+$'), '');

  if (result.isEmpty || result == '.' || result == '..') {
    return fallback;
  }

  final stem = result.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    result = '_$result';
  }

  return result.isEmpty ? fallback : result;
}

String _decodeFilename(String value) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}

String _stripWrappingQuotes(String value) {
  var result = value;
  while (result.length >= 2) {
    final first = result[0];
    final last = result[result.length - 1];
    final matches =
        (first == '"' && last == '"') ||
        (first == "'" && last == "'") ||
        (first == '“' && last == '”') ||
        (first == '‘' && last == '’') ||
        (first == '`' && last == '`');
    if (!matches) break;
    result = result.substring(1, result.length - 1).trim();
  }
  return result;
}
