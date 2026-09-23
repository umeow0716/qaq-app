import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/core/network_request_pool.dart';

void main() {
  test('one pool caps concurrent requests across simultaneous batches', () async {
    final pool = NetworkRequestPool(maxConnections: 8, retryDelay: Duration.zero);
    final release = Completer<void>();
    final firstEightStarted = Completer<void>();
    var active = 0;
    var maxActive = 0;
    var started = 0;

    Future<int?> request(Duration timeout) async {
      active++;
      started++;
      if (active > maxActive) maxActive = active;
      if (started == 8 && !firstEightStarted.isCompleted) {
        firstEightStarted.complete();
      }
      await release.future;
      active--;
      return 1;
    }

    final firstRun = pool.run<int>(List.generate(8, (_) => request));
    final secondRun = pool.run<int>(List.generate(8, (_) => request));

    await firstEightStarted.future;
    expect(active, 8);
    expect(maxActive, 8);

    release.complete();
    await Future.wait([firstRun, secondRun]);
    expect(maxActive, 8);
  });

  test('passes five second timeout and retries once', () async {
    final pool = NetworkRequestPool(retryDelay: Duration.zero);
    var attempts = 0;
    final seenTimeouts = <Duration>[];

    final result = await pool.execute<int>((timeout) async {
      attempts++;
      seenTimeouts.add(timeout);
      return attempts == 1 ? null : 42;
    });

    expect(result, 42);
    expect(attempts, 2);
    expect(seenTimeouts, everyElement(const Duration(seconds: 5)));
  });

  test('retries an application-level empty result', () async {
    final pool = NetworkRequestPool(retryDelay: Duration.zero);
    var attempts = 0;

    final result = await pool.execute<String>((timeout) async {
      attempts++;
      return attempts == 1 ? '' : 'ok';
    }, shouldRetry: (value) => value == null || value.isEmpty);

    expect(result, 'ok');
    expect(attempts, 2);
  });
}
