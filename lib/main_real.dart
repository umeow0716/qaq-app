// TODO: remove sdk version selector after migrating to null-safety.
// @dart=2.10
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/tat_app.dart';

import 'debug/log/log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Log.init();

  runZonedGuarded(
    runTATApp,
    (error, stackTrace) => Log.error(error, stackTrace),
  );
}
