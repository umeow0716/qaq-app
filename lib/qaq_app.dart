import 'package:bot_toast/bot_toast.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/route_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/generated/l10n.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:qaq_app/src/config/app_themes.dart';
import 'package:qaq_app/src/providers/app_provider.dart';
import 'package:qaq_app/src/providers/category_provider.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/util/language_util.dart';
import 'package:qaq_app/ui/pages/webview/web_view_page.dart';
import 'package:qaq_app/ui/screen/main_screen.dart';

typedef _FutureVoidCallBack = Future<void> Function();

Future<void> runQAQApp() async {
  final appDocDir = (await getApplicationDocumentsDirectory()).path;
  final CookieJar cookieJar = PersistCookieJar(storage: FileStorage('$appDocDir/.cookies'));

  const webViewPage = WebViewPage.instance;

  Future<void> handleAppDetached() async {
    await webViewPage.close();
  }

  await LocalStorage.instance.init(cookieJar: cookieJar);
  await LanguageUtil.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  WidgetsBinding.instance.addObserver(_QAQLifeCycleEventHandler(detachedCallBack: handleAppDetached));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
      ],
      child: const _QAQApp(),
    ),
  );
}

class _QAQApp extends StatelessWidget {
  const _QAQApp();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale?>(
    valueListenable: LanguageUtil.localeNotifier,
    builder: (context, locale, child) => Consumer<AppProvider>(
      builder: (context, appProvider, child) => GetMaterialApp(
        key: ValueKey(locale?.toLanguageTag()),
        title: AppConfig.appName,
        theme: AppThemes.lightTheme,
        navigatorKey: appProvider.navigatorKey,
        darkTheme: AppThemes.darkTheme,
        themeMode: appProvider.themeMode,
        locale: locale,
        localizationsDelegates: const [
          S.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: BotToastInit().call(context, child),
        ),
        navigatorObservers: [BotToastNavigatorObserver()],
        supportedLocales: S.delegate.supportedLocales,
        home: const MainScreen(),
        logWriterCallback: (String text, {bool? isError}) {
          Log.d(text);
        },
      ),
    ),
  );
}

class _QAQLifeCycleEventHandler extends WidgetsBindingObserver {
  _QAQLifeCycleEventHandler({required this.detachedCallBack});
  final _FutureVoidCallBack detachedCallBack;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.detached:
        await detachedCallBack();
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
}
