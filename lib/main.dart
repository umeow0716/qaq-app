import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/tat_app.dart';

import 'debug/log/log.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      Log.init();
      await runTATApp();
    },
    (error, stackTrace) => Log.error(error, stackTrace),
  );
}
