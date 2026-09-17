import 'dart:convert';
import 'dart:io';

enum CampusNetworkStatus { onCampus, offCampus, unknown }

class CampusNetworkDetector {
  CampusNetworkDetector._();

  static const _publicIpEndpoint = 'https://api.ipify.org?format=json';
  static const _cacheDuration = Duration(minutes: 2);

  static CampusNetworkStatus? _cachedStatus;
  static DateTime? _cachedAt;

  static Future<CampusNetworkStatus> detect() async {
    final now = DateTime.now();
    final cachedAt = _cachedAt;
    final cachedStatus = _cachedStatus;
    if (cachedAt != null && cachedStatus != null && now.difference(cachedAt) < _cacheDuration) {
      return cachedStatus;
    }

    final status = await _loadPublicIpStatus();
    _cachedStatus = status;
    _cachedAt = now;
    return status;
  }

  static Future<CampusNetworkStatus> _loadPublicIpStatus() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse(_publicIpEndpoint)).timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != HttpStatus.ok) return CampusNetworkStatus.unknown;

      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(body);
      if (decoded is! Map) return CampusNetworkStatus.unknown;

      final ip = decoded['ip'];
      return classifyPublicIp(ip is String ? ip : null);
    } on Object {
      return CampusNetworkStatus.unknown;
    } finally {
      client.close(force: true);
    }
  }

  static CampusNetworkStatus classifyPublicIp(String? ip) {
    final value = ip?.trim();
    if (value == null || value.isEmpty) return CampusNetworkStatus.unknown;

    final parts = value.split('.');
    if (parts.length != 4 || parts.any((part) => int.tryParse(part) == null)) {
      return CampusNetworkStatus.unknown;
    }

    return parts.first == '140' ? CampusNetworkStatus.onCampus : CampusNetworkStatus.offCampus;
  }

  static void clearCache() {
    _cachedStatus = null;
    _cachedAt = null;
  }
}
