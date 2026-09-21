import 'dart:async';
import 'dart:io';

import 'package:qaq_app/src/store/local_storage.dart';

import 'global_protect_connector.dart';
import 'global_protect_debug.dart';
import 'global_protect_http_client.dart';
import 'global_protect_idle.dart';
import 'global_protect_models.dart';
import 'global_protect_session_manager.dart';
import 'global_protect_session_cache.dart';

/// Process-local owner for the app's experimental GlobalProtect connection.
///
/// Credentials are never copied into this object. Every connection attempt
/// reads the account/password already held by [LocalStorage] at that moment.
class GlobalProtectAppSession {
  GlobalProtectAppSession._() : _connector = GlobalProtectConnector() {
    _idleController = GlobalProtectIdleController(timeout: idleTimeout, onIdle: _disconnectForIdle);
    _manager = GlobalProtectSessionManager(connect: _connectUsingCachedSessionOrPassword);
  }

  static const idleTimeout = Duration(minutes: 5);
  static final GlobalProtectAppSession instance = GlobalProtectAppSession._();

  final GlobalProtectConnector _connector;
  final GlobalProtectSessionCache _sessionCache = GlobalProtectSessionCache.instance;
  late final GlobalProtectIdleController _idleController;
  late final GlobalProtectSessionManager _manager;

  GlobalProtectHttpClient? _httpClient;
  GlobalProtectConnection? _httpConnection;
  Future<GlobalProtectHttpClient>? _httpInFlight;
  Future<void>? _disconnectInFlight;
  String? _connectedAccount;
  int _runtimeGeneration = 0;
  int _activityGeneration = 0;
  int? _activeActivityGeneration;

  GlobalProtectSessionState get state => _manager.state;
  bool get isConnected => _manager.isConnected;
  GlobalProtectConnection? get connection => _manager.connection;

  Future<GlobalProtectConnection> ensureConnected() async {
    final disconnecting = _disconnectInFlight;
    if (disconnecting != null) await disconnecting;

    final account = LocalStorage.instance.getAccount().trim();
    GlobalProtectDebug.log('ensureConnected state=${_manager.state.name} accountPresent=${account.isNotEmpty}');
    if (account.isEmpty) {
      GlobalProtectDebug.log('account unavailable; refusing GP connection');
      throw const GlobalProtectCredentialsUnavailableException();
    }

    if (_manager.isConnected && _connectedAccount != account) {
      GlobalProtectDebug.log('saved account changed; reconnecting GP session');
      await disconnect();
    }

    // A new request arriving just before the idle deadline must cancel the
    // pending idle disconnect before any await can yield to the timer.
    if (_manager.isConnected) _idleController.activity();

    final runtimeGeneration = _runtimeGeneration;
    try {
      final connection = await _manager.ensureConnected();
      if (runtimeGeneration != _runtimeGeneration) {
        throw StateError('GlobalProtect runtime was reset while connecting.');
      }
      _connectedAccount = account;
      _idleController.activity();
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
        onError: (Object _, StackTrace _) {
          if (identical(_httpInFlight, future)) _httpInFlight = null;
        },
      ),
    );
    return future;
  }

  Future<GlobalProtectHttpClient> _ensureHttpClient() async {
    final runtimeGeneration = _runtimeGeneration;
    final connection = await ensureConnected();
    if (runtimeGeneration != _runtimeGeneration) {
      throw StateError('GlobalProtect runtime was reset while creating an HTTP client.');
    }
    final existing = _httpClient;
    if (existing != null && identical(_httpConnection, connection)) {
      GlobalProtectDebug.log('reusing GP-backed HttpClient');
      return existing;
    }

    if (existing != null) {
      await existing.close(force: true);
    }

    if (runtimeGeneration != _runtimeGeneration) {
      throw StateError('GlobalProtect runtime was reset while creating an HTTP client.');
    }

    GlobalProtectDebug.log('creating GP-backed HttpClient');
    final next = GlobalProtectHttpClient.fromConnection(connection);
    _httpClient = next;
    _httpConnection = connection;
    return next;
  }

  Future<GlobalProtectConnection> _connectUsingCachedSessionOrPassword() async {
    final runtimeGeneration = _runtimeGeneration;
    final username = LocalStorage.instance.getAccount().trim();
    if (username.isEmpty) {
      throw const GlobalProtectCredentialsUnavailableException();
    }

    final cached = await _sessionCache.readForAccount(username);

    if (cached != null) {
      GlobalProtectDebug.log('cached GP session found; validating with gateway ${cached.gateway.host}');
      try {
        final connection = await _connector.resumeWithSession(
          gateway: cached.gateway,
          session: cached.session,
          trace: GlobalProtectDebug.log,
          transportTrace: (message) => GlobalProtectDebug.log('esp $message'),
        );
        if (runtimeGeneration != _runtimeGeneration) {
          await connection.transport.close();
          throw StateError('GlobalProtect runtime was reset while resuming a cached session.');
        }
        GlobalProtectDebug.log('cached GP session resumed');
        return _trackConnectionActivity(connection);
      } on GlobalProtectSessionRejectedException catch (error, stackTrace) {
        GlobalProtectDebug.error('cached GP session rejected', error, stackTrace);
        try {
          await _sessionCache.clear();
        } catch (cacheError, cacheStackTrace) {
          GlobalProtectDebug.error('GP cache clear', cacheError, cacheStackTrace);
        }
      }
    }

    if (runtimeGeneration != _runtimeGeneration) {
      throw StateError('GlobalProtect runtime was reset before password login.');
    }

    final password = LocalStorage.instance.getPassword();
    GlobalProtectDebug.log('starting GP password login; passwordPresent=${password.isNotEmpty}');
    if (password.isEmpty) {
      throw const GlobalProtectCredentialsUnavailableException();
    }

    try {
      final connection = await _connector.connectWithPassword(
        username: username,
        password: password,
        trace: GlobalProtectDebug.log,
        transportTrace: (message) => GlobalProtectDebug.log('esp $message'),
      );
      if (runtimeGeneration != _runtimeGeneration) {
        await connection.transport.close();
        throw StateError('GlobalProtect runtime was reset while password login was in flight.');
      }
      try {
        await _sessionCache.save(account: username, connection: connection);
        GlobalProtectDebug.log('GP session cached securely');
      } catch (cacheError, cacheStackTrace) {
        GlobalProtectDebug.error('GP cache write', cacheError, cacheStackTrace);
      }
      GlobalProtectDebug.log('GP password login completed');
      return _trackConnectionActivity(connection);
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('GP password login', error, stackTrace);
      rethrow;
    }
  }

  GlobalProtectConnection _trackConnectionActivity(GlobalProtectConnection connection) {
    final generation = ++_activityGeneration;
    _activeActivityGeneration = generation;
    return GlobalProtectConnection(
      gateway: connection.gateway,
      session: connection.session,
      config: connection.config,
      transport: GlobalProtectActivityTransport(
        delegate: connection.transport,
        onActivity: () => _recordTransportActivity(generation),
      ),
    );
  }

  void _recordTransportActivity(int generation) {
    if (generation != _activeActivityGeneration) return;
    _idleController.activity();
  }

  Future<void> _disconnectForIdle() async {
    if (!_manager.isConnected) return;
    GlobalProtectDebug.log('GP idle for ${idleTimeout.inMinutes} minutes; disconnecting live session');
    try {
      await disconnect();
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('idle disconnect', error, stackTrace);
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

  Future<void> disconnectAndClearCachedSession() async {
    try {
      await disconnect();
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('GP disconnect during logout', error, stackTrace);
    }

    try {
      await _sessionCache.clear();
    } catch (error, stackTrace) {
      GlobalProtectDebug.error('GP cache clear during logout', error, stackTrace);
    }
  }

  Future<void> disconnect() {
    final inFlight = _disconnectInFlight;
    if (inFlight != null) return inFlight;

    _idleController.cancel();
    _activeActivityGeneration = null;
    final future = _performDisconnect();
    _disconnectInFlight = future;
    unawaited(
      future.then<void>(
        (_) => _clearDisconnectInFlight(future),
        onError: (Object _, StackTrace _) => _clearDisconnectInFlight(future),
      ),
    );
    return future;
  }

  Future<void> _performDisconnect() async {
    _runtimeGeneration++;
    _httpInFlight = null;
    await _closeHttpClient();
    _connectedAccount = null;
    if (_manager.state != GlobalProtectSessionState.disposed) {
      await _manager.disconnect();
    }
  }

  void _clearDisconnectInFlight(Future<void> future) {
    if (identical(_disconnectInFlight, future)) _disconnectInFlight = null;
  }
}

class GlobalProtectCredentialsUnavailableException implements Exception {
  const GlobalProtectCredentialsUnavailableException();

  @override
  String toString() => 'No saved NTUT account/password is available for GlobalProtect.';
}
