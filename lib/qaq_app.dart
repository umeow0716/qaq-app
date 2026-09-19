import 'package:bot_toast/bot_toast.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/generated/l10n.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:qaq_app/src/config/app_themes.dart';
import 'package:qaq_app/src/connector/blocked_cookies.dart';
import 'package:qaq_app/src/connector/interceptors/request_interceptor.dart';
import 'package:qaq_app/src/connector/interceptors/response_cookie_filter.dart';
import 'package:qaq_app/src/providers/app_provider.dart';
import 'package:qaq_app/src/providers/category_provider.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/ui/pages/webview/web_view_page.dart';
import 'package:qaq_app/ui/screen/main_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/route_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

typedef _FutureVoidCallBack = Future<void> Function();

Future<void> runQAQApp() async {
  final appDocDir = (await getApplicationDocumentsDirectory()).path;
  final CookieJar cookieJar = PersistCookieJar(storage: FileStorage('$appDocDir/.cookies'));

  final apiInterceptors = [
    ResponseCookieFilter(blockedCookieNamePatterns: blockedCookieNamePatterns),
    CookieManager(cookieJar),
    RequestInterceptors(),
  ];
  const webViewPage = WebViewPage.instance;

  Future<void> handleAppDetached() async {
    await webViewPage.close();
  }

  await LocalStorage.instance.init(httpClientInterceptors: apiInterceptors, cookieJar: cookieJar);
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
  Widget build(BuildContext context) => Consumer<AppProvider>(
    builder: (context, appProvider, child) => GetMaterialApp(
      title: AppConfig.appName,
      theme: appProvider.theme,
      navigatorKey: appProvider.navigatorKey,
      darkTheme: AppThemes.darkTheme,
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
