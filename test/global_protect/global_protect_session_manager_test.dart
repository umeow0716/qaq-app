import 'dart:async';
import 'dart:typed_data';

import 'package:qaq_app/src/connector/global_protect/global_protect_transport.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_models.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements GlobalProtectTransport {
  @override
  Stream<Uint8List> get packets => const Stream<Uint8List>.empty();

  @override
  Future<void> sendIpv4(Uint8List packet) async {}

  @override
  Future<void> sendIpv6(Uint8List packet) async {}

  @override
  Future<void> close() async {}
}

class _FakeConnection implements GlobalProtectConnection {
  _FakeConnection(this.id);

  final int id;

  @override
  GlobalProtectTunnelConfig get config => throw UnimplementedError();

  @override
  Uri get gateway => throw UnimplementedError();

  @override
  GlobalProtectSession get session => throw UnimplementedError();

  @override
  GlobalProtectTransport get transport => _FakeTransport();
}

void main() {
  test('reuses the active connection', () async {
    var connectCalls = 0;
    final events = StreamController<void>.broadcast();
    final connection = _FakeConnection(1);
    final manager = GlobalProtectSessionManager(
      connect: () async {
        connectCalls++;
        return connection;
      },
      disconnect: (_) async {},
      connectionEvents: (_) => events.stream,
    );

    final first = await manager.ensureConnected();
    final second = await manager.ensureConnected();

    expect(first, same(connection));
    expect(second, same(connection));
    expect(connectCalls, 1);
    expect(manager.state, GlobalProtectSessionState.connected);

    await manager.dispose();
    await events.close();
  });

  test('deduplicates concurrent connection attempts', () async {
    var connectCalls = 0;
    final completer = Completer<GlobalProtectConnection>();
    final events = StreamController<void>.broadcast();
    final connection = _FakeConnection(1);
    final manager = GlobalProtectSessionManager(
      connect: () {
        connectCalls++;
        return completer.future;
      },
      disconnect: (_) async {},
      connectionEvents: (_) => events.stream,
    );

    final first = manager.ensureConnected();
    final second = manager.ensureConnected();
    expect(connectCalls, 1);

    completer.complete(connection);
    expect(await first, same(connection));
    expect(await second, same(connection));

    await manager.dispose();
    await events.close();
  });

  test('returns to disconnected when connect fails', () async {
    final manager = GlobalProtectSessionManager(
      connect: () async => throw const FormatException('bad credentials'),
      disconnect: (_) async {},
      connectionEvents: (_) => const Stream<void>.empty(),
    );

    await expectLater(manager.ensureConnected(), throwsFormatException);
    expect(manager.state, GlobalProtectSessionState.disconnected);
    expect(manager.snapshot.error, isA<FormatException>());

    await manager.dispose();
  });

  test('disconnect closes and clears the active connection', () async {
    final events = StreamController<void>.broadcast();
    final connection = _FakeConnection(1);
    GlobalProtectConnection? disconnected;
    final manager = GlobalProtectSessionManager(
      connect: () async => connection,
      disconnect: (value) async {
        disconnected = value;
      },
      connectionEvents: (_) => events.stream,
    );

    await manager.ensureConnected();
    await manager.disconnect();

    expect(disconnected, same(connection));
    expect(manager.connection, isNull);
    expect(manager.state, GlobalProtectSessionState.disconnected);

    await manager.dispose();
    await events.close();
  });

  test('marks the session disconnected when the transport event stream ends', () async {
    final events = StreamController<void>.broadcast();
    final connection = _FakeConnection(1);
    final manager = GlobalProtectSessionManager(
      connect: () async => connection,
      disconnect: (_) async {},
      connectionEvents: (_) => events.stream,
    );

    await manager.ensureConnected();
    await events.close();
    await Future<void>.delayed(Duration.zero);

    expect(manager.connection, isNull);
    expect(manager.state, GlobalProtectSessionState.disconnected);

    await manager.dispose();
  });
}
