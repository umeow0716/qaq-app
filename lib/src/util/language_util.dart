import 'package:flutter/cupertino.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/generated/l10n.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/model/setting/setting_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';

enum LangEnum { en, zh }

class LanguageUtil {
  static final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

  static Future<void> init() async {
    final otherSetting = LocalStorage.instance.getOtherSetting();
    final locale = otherSetting.lang.isEmpty
        ? _resolveSupportedLocale(WidgetsBinding.instance.platformDispatcher.locale)
        : string2Locale(otherSetting.lang);
    await load(locale);
  }

  static List<Locale> get getSupportLocale => S.delegate.supportedLocales;

  static Future<void> load(Locale locale) async {
    final resolvedLocale = _resolveSupportedLocale(locale);
    await R.load(resolvedLocale);

    final lang = locale2String(resolvedLocale);
    final OtherSettingJson otherSetting = LocalStorage.instance.getOtherSetting();
    if (otherSetting.lang != lang) {
      otherSetting.lang = lang;
      LocalStorage.instance.setOtherSetting(otherSetting);
      await LocalStorage.instance.saveOtherSetting();
      await LocalStorage.instance.clearCourseTableList();
      await LocalStorage.instance.clearCourseSetting();
    }

    localeNotifier.value = resolvedLocale;
  }

  static String locale2String(Locale locale) {
    final countryCode = locale.countryCode ?? "";
    final languageCode = locale.languageCode;
    return '${countryCode}_$languageCode';
  }

  static Locale string2Locale(String lang) {
    for (final locale in getSupportLocale) {
      if (locale2String(locale) == lang || locale.toLanguageTag() == lang) {
        return locale;
      }
    }

    final parts = lang.split('_').where((part) => part.isNotEmpty).toList();
    for (final locale in getSupportLocale) {
      if (!parts.contains(locale.languageCode)) continue;
      final countryCode = locale.countryCode;
      if (countryCode == null || parts.contains(countryCode)) {
        return locale;
      }
    }

    return getSupportLocale.first;
  }

  static Future<void> setLangByIndex(LangEnum langEnum) async {
    final locale = getSupportLocale[langEnum.index];
    final portalLocale = langEnum == LangEnum.zh ? 'zh_TW' : 'en';

    // Keep nPortal in the same language as QAQ. This request intentionally
    // happens before the local locale is committed so SSO pages opened right
    // after the switch already render in the requested language. Network or
    // session failures must not prevent the user from changing QAQ's UI.
    try {
      await NTUTConnector.reloadLocale(portalLocale);
    } catch (error, stackTrace) {
      Log.eWithStack('nPortal locale switch failed: $error', stackTrace);
    }

    await load(locale);
  }

  static LangEnum getLangIndex() {
    final locale = localeNotifier.value ?? string2Locale(LocalStorage.instance.getOtherSetting().lang);
    return locale.languageCode == 'en' ? LangEnum.en : LangEnum.zh;
  }

  static Locale _resolveSupportedLocale(Locale requestedLocale) {
    for (final locale in getSupportLocale) {
      if (locale.languageCode == requestedLocale.languageCode && locale.countryCode == requestedLocale.countryCode) {
        return locale;
      }
    }

    for (final locale in getSupportLocale) {
      if (locale.languageCode == requestedLocale.languageCode) {
        return locale;
      }
    }

    return getSupportLocale.first;
  }
}
