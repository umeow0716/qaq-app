import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

class TabPage {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget tab;
  final Widget tabPage;

  factory TabPage(String title, IconData icons, Widget initPage, {bool useNavigatorKey = false}) {
    final navigatorKey = GlobalKey<NavigatorState>();
    final tab = Column(
      children: <Widget>[
        Icon(icons),
        FittedBox(
          child: AutoSizeText(title, maxLines: 1, minFontSize: 6),
        ),
      ],
    );
    final tabPage = useNavigatorKey
        ? Navigator(
            key: navigatorKey,
            onGenerateRoute: (routeSettings) => MaterialPageRoute<void>(builder: (context) => initPage),
          )
        : initPage;
    return TabPage._(navigatorKey, tab, tabPage);
  }

  const TabPage._(this.navigatorKey, this.tab, this.tabPage);
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
