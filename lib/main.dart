import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:qaq_app/qaq_app.dart';

import 'debug/log/log.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    Log.init();
    await runQAQApp();
  }, (error, stackTrace) => Log.error(error, stackTrace));
}
