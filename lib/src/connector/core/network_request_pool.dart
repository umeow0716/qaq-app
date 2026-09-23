import 'dart:async';
import 'dart:collection';

typedef NetworkPoolRequest<T> = Future<T?> Function(Duration timeout);
typedef NetworkPoolRetryPredicate<T> = bool Function(T? value);
typedef NetworkPoolComplete<T> = void Function(int index, T? value);

class NetworkRequestPool {
  NetworkRequestPool({
    this.maxConnections = 8,
    this.timeout = const Duration(seconds: 5),
    this.retries = 1,
    this.retryDelay = const Duration(milliseconds: 200),
  }) : assert(maxConnections > 0),
       assert(retries >= 0);

  static final NetworkRequestPool shared = NetworkRequestPool();

  final int maxConnections;
  final Duration timeout;
  final int retries;
  final Duration retryDelay;

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<List<T?>> run<T>(
    Iterable<NetworkPoolRequest<T>> requests, {
    NetworkPoolRetryPredicate<T>? shouldRetry,
    NetworkPoolComplete<T>? onComplete,
  }) {
    final jobs = requests.toList(growable: false);
    return Future.wait<T?>(
      jobs.asMap().entries.map((entry) async {
        final value = await execute<T>(entry.value, shouldRetry: shouldRetry);
        onComplete?.call(entry.key, value);
        return value;
      }),
      eagerError: false,
    );
  }

  Future<T?> execute<T>(NetworkPoolRequest<T> request, {NetworkPoolRetryPredicate<T>? shouldRetry}) async {
    await _acquire();
    try {
      T? lastValue;
      for (var attempt = 0; attempt <= retries; attempt++) {
        try {
          final value = await request(timeout);
          lastValue = value;
          final retry = shouldRetry?.call(value) ?? value == null;
          if (!retry || attempt == retries) return value;
        } catch (_) {
          if (attempt == retries) return null;
        }

        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
      return lastValue;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConnections) {
      _active++;
      return Future<void>.value();
    }

    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
