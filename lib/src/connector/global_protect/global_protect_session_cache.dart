import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'global_protect_models.dart';

class GlobalProtectCachedSession {
  const GlobalProtectCachedSession({
    required this.account,
    required this.gateway,
    required this.session,
    required this.cachedAt,
  });

  final String account;
  final Uri gateway;
  final GlobalProtectSession session;
  final DateTime cachedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'account': account,
        'gateway': gateway.toString(),
        'session': session.values,
        'cachedAt': cachedAt.toUtc().toIso8601String(),
      };

  static GlobalProtectCachedSession? fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) return null;

    final account = json['account'];
    final gatewayText = json['gateway'];
    final rawSession = json['session'];
    final cachedAtText = json['cachedAt'];
    if (account is! String || account.trim().isEmpty) return null;
    if (gatewayText is! String) return null;
    if (rawSession is! Map) return null;
    if (cachedAtText is! String) return null;

    final gateway = Uri.tryParse(gatewayText);
    final cachedAt = DateTime.tryParse(cachedAtText);
    if (gateway == null || gateway.host.isEmpty || cachedAt == null) return null;

    final values = <String, String>{};
    for (final entry in rawSession.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) values[key] = value;
    }

    final session = GlobalProtectSession(values: values);
    if (session.user.isEmpty || session.authCookie.isEmpty) return null;

    return GlobalProtectCachedSession(
      account: account.trim(),
      gateway: gateway,
      session: session,
      cachedAt: cachedAt,
    );
  }
}

class GlobalProtectSessionCache {
  GlobalProtectSessionCache._();

  static final GlobalProtectSessionCache instance = GlobalProtectSessionCache._();

  static const _cacheKey = 'global_protect_session_v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  int _generation = 0;

  Future<GlobalProtectCachedSession?> readForAccount(String account) async {
    final normalizedAccount = account.trim();
    if (normalizedAccount.isEmpty) return null;

    final raw = await _storage.read(key: _cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        await clear();
        return null;
      }

      final cached = GlobalProtectCachedSession.fromJson(decoded);
      if (cached == null) {
        await clear();
        return null;
      }

      if (cached.account != normalizedAccount) {
        await clear();
        return null;
      }

      return cached;
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<void> save({
    required String account,
    required GlobalProtectConnection connection,
  }) async {
    final normalizedAccount = account.trim();
    if (normalizedAccount.isEmpty) return;
    if (connection.session.user.isEmpty || connection.session.authCookie.isEmpty) return;

    final generation = _generation;
    final cached = GlobalProtectCachedSession(
      account: normalizedAccount,
      gateway: connection.gateway,
      session: connection.session,
      cachedAt: DateTime.now().toUtc(),
    );
    await _storage.write(key: _cacheKey, value: json.encode(cached.toJson()));
    if (generation != _generation) {
      await _storage.delete(key: _cacheKey);
    }
  }

  Future<void> clear() async {
    _generation++;
    await _storage.delete(key: _cacheKey);
  }
}
