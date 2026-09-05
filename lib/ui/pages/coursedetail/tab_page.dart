import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

class TabPage {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final Widget tab;
  late final Widget tabPage;

  TabPage(String title, IconData icons, Widget initPage, {bool useNavigatorKey = false}) {
    tab = Column(
      children: <Widget>[
        Icon(icons),
        FittedBox(
          child: AutoSizeText(title, maxLines: 1, minFontSize: 6),
        ),
      ],
    );
    tabPage = useNavigatorKey
        ? Navigator(
            key: navigatorKey,
            onGenerateRoute: (routeSettings) => MaterialPageRoute<void>(builder: (context) => initPage),
          )
        : initPage;
  }
}

class TabPageList {
  final List<TabPage> tabPageList = <TabPage>[];

  void add(TabPage page) => tabPageList.add(page);

  List<Widget> get getTabPageList => tabPageList.map((tabPage) => tabPage.tabPage).toList();

  List<Widget> getTabList(BuildContext context) {
    final pages = <Widget>[];
    final width = MediaQuery.of(context).size.width / length;
    for (final tabPage in tabPageList) {
      pages.add(SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
          child: tabPage.tab,
        ),
      ));
    }
    return pages;
  }

  Widget getPage(int index) => tabPageList[index].tabPage;
  GlobalKey<NavigatorState> getKey(int index) => tabPageList[index].navigatorKey;
  int get length => tabPageList.length;
}
