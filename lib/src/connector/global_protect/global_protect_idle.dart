import 'dart:async';
import 'dart:typed_data';

import 'global_protect_transport.dart';

typedef GlobalProtectIdleCallback = FutureOr<void> Function();
typedef GlobalProtectIdleTimerFactory = Timer Function(Duration duration, void Function() callback);

Timer _defaultIdleTimerFactory(Duration duration, void Function() callback) => Timer(duration, callback);

/// Resets an idle countdown whenever [activity] is called.
///
/// The callback is generation-guarded, so a stale timer that fires after a
/// newer activity signal cannot disconnect a newly active session.
class GlobalProtectIdleController {
  GlobalProtectIdleController({
    required Duration timeout,
    required GlobalProtectIdleCallback onIdle,
    GlobalProtectIdleTimerFactory timerFactory = _defaultIdleTimerFactory,
  }) : this._(timeout, onIdle, timerFactory);

  GlobalProtectIdleController._(this.timeout, this.onIdle, this._timerFactory);

  final Duration timeout;
  final GlobalProtectIdleCallback onIdle;
  final GlobalProtectIdleTimerFactory _timerFactory;

  Timer? _timer;
  int _generation = 0;

  void activity() {
    final generation = ++_generation;
    _timer?.cancel();
    _timer = _timerFactory(timeout, () {
      if (generation != _generation) return;
      _timer = null;
      unawaited(Future<void>.sync(onIdle));
    });
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}

/// Adds activity observation to a GlobalProtect packet transport without
/// changing the packet bytes or transport close semantics.
///
/// Incoming packets are subscribed to exactly once and rebroadcast, avoiding
/// one activity callback per virtual TCP listener.
class GlobalProtectActivityTransport implements GlobalProtectTransport {
  GlobalProtectActivityTransport({required GlobalProtectTransport delegate, required void Function() onActivity})
    : this._(delegate, onActivity);

  GlobalProtectActivityTransport._(this._delegate, this._onActivity) {
    _subscription = _delegate.packets.listen(
      (packet) {
        _onActivity();
        if (!_packets.isClosed) _packets.add(packet);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_packets.isClosed) _packets.addError(error, stackTrace);
      },
      onDone: () {
        if (!_packets.isClosed) unawaited(_packets.close());
      },
      cancelOnError: false,
    );
  }

  final GlobalProtectTransport _delegate;
  final void Function() _onActivity;
  final StreamController<Uint8List> _packets = StreamController<Uint8List>.broadcast(sync: true);
  late final StreamSubscription<Uint8List> _subscription;
  bool _closed = false;

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Future<void> sendIpv4(Uint8List packet) {
    _onActivity();
    return _delegate.sendIpv4(packet);
  }

  @override
  Future<void> sendIpv6(Uint8List packet) {
    _onActivity();
    return _delegate.sendIpv6(packet);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      await _delegate.close();
    } catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    } finally {
      await _subscription.cancel();
      if (!_packets.isClosed) await _packets.close();
    }

    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }
}
