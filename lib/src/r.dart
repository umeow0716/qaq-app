import 'package:flutter/widgets.dart';

import '../generated/l10n.dart';

class R {
  static S get current => S.current;

  static Future<S> load(Locale locale) => S.load(locale);
}
