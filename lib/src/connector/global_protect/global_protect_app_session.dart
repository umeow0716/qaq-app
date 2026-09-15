import 'dart:async';
import 'dart:io';

import 'package:flutter_app/src/store/local_storage.dart';

import 'global_protect_connector.dart';
import 'global_protect_debug.dart';
import 'global_protect_http_client.dart';
import 'global_protect_models.dart';
import 'global_protect_session_manager.dart';

/// Process-local owner for the app's experimental GlobalProtect connection.
///
/// Credentials are never copied into this object. Every connection attempt
/// reads the account/password already held by [LocalStorage] at that moment.
class GlobalProtectAppSession {
  GlobalProtectAppSession._()
      : _connector = GlobalProtectConnector() {
    _manager = GlobalProtectSessionManager(connect: _connectUsingCurrentLogin);
  }

  static final GlobalProtectAppSession instance = GlobalProtectAppSession._();

  final GlobalProtectConnector _connector;
  late final GlobalProtectSessionManager _manager;

  GlobalProtectHttpClient? _httpClient;
  GlobalProtectConnection? _httpConnection;
  Future<GlobalProtectHttpClient>? _httpInFlight;
  String? _connectedAccount;

  GlobalProtectSessionState get state => _manager.state;
  bool get isConnected => _manager.isConnected;
  GlobalProtectConnection? get connection => _manager.connection;

  Future<GlobalProtectConnection> ensureConnected() async {
    final account = LocalStorage.instance.getAccount().trim();
    final password = LocalStorage.instance.getPassword();
    GlobalProtectDebug.log(
      'ensureConnected state=${_manager.state.name} '
      'accountPresent=${account.isNotEmpty} passwordPresent=${password.isNotEmpty}',
    );
    if (account.isEmpty || password.isEmpty) {
      GlobalProtectDebug.log('credentials unavailable; refusing GP connection');
      throw const GlobalProtectCredentialsUnavailableException();
    }

    if (_manager.isConnected && _connectedAccount != account) {
      GlobalProtectDebug.log('saved account changed; reconnecting GP session');
      await _closeHttpClient();
      await _manager.disconnect();
    }
    try {
      final connection = await _manager.ensureConnected();
      GlobalProtectDebug.log(
        'session ready gateway=${connection.gateway.host} '
        'transport=esp tunnelIp=${connection.config.ipAddress ?? '-'}',
      );
      return connection;
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('ensureConnected', error, stackTrace);
      rethrow;
    }
  }

  Future<GlobalProtectHttpClient> ensureHttpClient() {
    final inFlight = _httpInFlight;
    if (inFlight != null) return inFlight;

    final future = _ensureHttpClient();
    _httpInFlight = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_httpInFlight, future)) _httpInFlight = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_httpInFlight, future)) _httpInFlight = null;
        },
      ),
    );
    return future;
  }

  Future<GlobalProtectHttpClient> _ensureHttpClient() async {
    final connection = await ensureConnected();
    final existing = _httpClient;
    if (existing != null && identical(_httpConnection, connection)) {
      GlobalProtectDebug.log('reusing GP-backed HttpClient');
      return existing;
    }

    if (existing != null) {
      await existing.close(force: true);
    }

    GlobalProtectDebug.log('creating GP-backed HttpClient');
    final next = GlobalProtectHttpClient.fromConnection(connection);
    _httpClient = next;
    _httpConnection = connection;
    return next;
  }

  Future<GlobalProtectConnection> _connectUsingCurrentLogin() async {
    final username = LocalStorage.instance.getAccount().trim();
    final password = LocalStorage.instance.getPassword();

    GlobalProtectDebug.log(
      'starting GP login from saved NTUT credentials; '
      'accountPresent=${username.isNotEmpty} passwordPresent=${password.isNotEmpty}',
    );
    if (username.isEmpty || password.isEmpty) {
      throw const GlobalProtectCredentialsUnavailableException();
    }

    try {
      final connection = await _connector.connectWithPassword(
        username: username,
        password: password,
        trace: GlobalProtectDebug.log,
        transportTrace: (message) => GlobalProtectDebug.log('esp $message'),
      );
      _connectedAccount = username;
      GlobalProtectDebug.log('GP login completed');
      return connection;
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('GP login', error, stackTrace);
      rethrow;
    }
  }

  Future<InternetAddress> resolveIpv4(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      if (literal.type != InternetAddressType.IPv4) {
        throw UnsupportedError('GlobalProtect app bridge currently supports IPv4 only.');
      }
      return literal;
    }

    final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    if (addresses.isEmpty) throw SocketException('No IPv4 address found for $host');
    return addresses.first;
  }

  Future<void> _closeHttpClient() async {
    final http = _httpClient;
    _httpClient = null;
    _httpConnection = null;
    if (http != null) await http.close(force: true);
  }

  Future<void> disconnect() async {
    await _closeHttpClient();
    _connectedAccount = null;
    if (_manager.state != GlobalProtectSessionState.disposed) {
      await _manager.disconnect();
    }
  }
}

class GlobalProtectCredentialsUnavailableException implements Exception {
  const GlobalProtectCredentialsUnavailableException();

  @override
  String toString() => 'No saved NTUT account/password is available for GlobalProtect.';
}
