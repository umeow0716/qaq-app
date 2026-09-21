import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_idle.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_transport.dart';

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);

  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

class _ManualTimerFactory {
  final List<_ManualTimer> timers = <_ManualTimer>[];

  Timer create(Duration _, void Function() callback) {
    final timer = _ManualTimer(callback);
    timers.add(timer);
    return timer;
  }
}

class _FakeTransport implements GlobalProtectTransport {
  final StreamController<Uint8List> controller = StreamController<Uint8List>.broadcast();
  final List<Uint8List> sentIpv4 = <Uint8List>[];
  final List<Uint8List> sentIpv6 = <Uint8List>[];
  bool closed = false;

  @override
  Stream<Uint8List> get packets => controller.stream;

  @override
  Future<void> sendIpv4(Uint8List packet) async {
    sentIpv4.add(Uint8List.fromList(packet));
  }

  @override
  Future<void> sendIpv6(Uint8List packet) async {
    sentIpv6.add(Uint8List.fromList(packet));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controller.close();
  }
}

void main() {
  test('idle controller ignores a stale timer after new activity', () async {
    final timers = _ManualTimerFactory();
    var idleCalls = 0;
    final controller = GlobalProtectIdleController(
      timeout: const Duration(minutes: 5),
      onIdle: () async {
        idleCalls++;
      },
      timerFactory: timers.create,
    );

    controller.activity();
    controller.activity();

    expect(timers.timers, hasLength(2));
    timers.timers.first.fire();
    await Future<void>.delayed(Duration.zero);
    expect(idleCalls, 0);

    timers.timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(idleCalls, 1);
  });

  test('cancel prevents the pending idle callback', () async {
    final timers = _ManualTimerFactory();
    var idleCalls = 0;
    final controller = GlobalProtectIdleController(
      timeout: const Duration(minutes: 5),
      onIdle: () => idleCalls++,
      timerFactory: timers.create,
    );

    controller.activity();
    controller.cancel();
    timers.timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(idleCalls, 0);
  });

  test('activity transport observes each underlying packet once', () async {
    final delegate = _FakeTransport();
    var activityCalls = 0;
    final transport = GlobalProtectActivityTransport(delegate: delegate, onActivity: () => activityCalls++);
    final first = <Uint8List>[];
    final second = <Uint8List>[];
    final firstSub = transport.packets.listen(first.add);
    final secondSub = transport.packets.listen(second.add);

    delegate.controller.add(Uint8List.fromList(<int>[1, 2, 3]));
    await Future<void>.delayed(Duration.zero);

    expect(activityCalls, 1);
    expect(first.single, <int>[1, 2, 3]);
    expect(second.single, <int>[1, 2, 3]);

    await firstSub.cancel();
    await secondSub.cancel();
    await transport.close();
  });

  test('activity transport observes outgoing IPv4 and IPv6 packets', () async {
    final delegate = _FakeTransport();
    var activityCalls = 0;
    final transport = GlobalProtectActivityTransport(delegate: delegate, onActivity: () => activityCalls++);

    await transport.sendIpv4(Uint8List.fromList(<int>[4]));
    await transport.sendIpv6(Uint8List.fromList(<int>[6]));

    expect(activityCalls, 2);
    expect(delegate.sentIpv4.single, <int>[4]);
    expect(delegate.sentIpv6.single, <int>[6]);

    await transport.close();
  });
}
