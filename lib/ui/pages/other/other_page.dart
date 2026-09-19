import 'package:cached_network_image/cached_network_image.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:flutter/material.dart';
import 'package:qaq_app/debug/log/log.dart';
// import 'package:qaq_app/src/config/app_config.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/file/file_store.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/task/ntut/ntut_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/ui/other/msg_dialog.dart';
import 'package:qaq_app/ui/other/route_utils.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';

enum OnListViewPress { setting, fileViewer, logout, about, login, subSystem }

class OtherPage extends StatefulWidget {
  final PageController pageController;

  const OtherPage(this.pageController, {super.key});

  @override
  State<OtherPage> createState() => _OtherPageState();
}

class _OtherPageState extends State<OtherPage> {
  final List<Map<String, Object?>> optionList = [
    {
      "icon": EvaIcons.settings2Outline,
      "color": Colors.orange,
      "title": R.current.setting,
      "onPress": OnListViewPress.setting,
    },
    {
      "icon": Icons.computer,
      "color": Colors.lightBlue,
      "title": R.current.informationSystem,
      "onPress": OnListViewPress.subSystem,
    },
    {
      "icon": EvaIcons.downloadOutline,
      "color": Colors.yellow[700],
      "title": R.current.fileViewer,
      "onPress": OnListViewPress.fileViewer,
    },
    if (LocalStorage.instance.getPassword().isNotEmpty)
      {
        "icon": EvaIcons.undoOutline,
        "color": Colors.teal[400],
        "title": R.current.logout,
        "onPress": OnListViewPress.logout,
      },
    if (LocalStorage.instance.getPassword().isEmpty)
      {"icon": EvaIcons.logIn, "color": Colors.teal[400], "title": R.current.login, "onPress": OnListViewPress.login},
    {
      "icon": EvaIcons.infoOutline,
      "color": Colors.lightBlue,
      "title": R.current.about,
      "onPress": OnListViewPress.about,
    },
  ];

  @override
  void initState() {
    super.initState();
  }

  void _onListViewPress(OnListViewPress value) async {
    switch (value) {
      case OnListViewPress.subSystem:
        RouteUtils.toSubSystemPage(R.current.informationSystem, null);
        break;
      case OnListViewPress.logout:
        MsgDialogParameter parameter = MsgDialogParameter(
          desc: R.current.logoutWarning,
          dialogType: DialogType.warning,
          title: R.current.warning,
          okButtonText: R.current.sure,
          onOkButtonClicked: () {
            Get.back();
            TaskFlow.resetLoginStatus();
            LocalStorage.instance.logout().then((_) => RouteUtils.toLoginScreen());
          },
        );
        MsgDialog(parameter).show();
        break;
      case OnListViewPress.login:
        RouteUtils.toLoginScreen().then((value) {
          if (value == true) widget.pageController.jumpToPage(0);
        });
        break;
      case OnListViewPress.fileViewer:
        FileStore.findLocalPath().then((filePath) {
          RouteUtils.toFileViewerPage(R.current.fileViewer, filePath);
        });
        break;
      case OnListViewPress.about:
        RouteUtils.toAboutPage();
        break;
      case OnListViewPress.setting:
        RouteUtils.toSettingPage(widget.pageController);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(R.current.titleOther)),
      body: Column(
        children: <Widget>[
          if (LocalStorage.instance.getAccount().isNotEmpty)
            SizedBox(
              child: FutureBuilder<Map<String, Map<String, String>>>(
                future: NTUTConnector.getUserImageRequestInfo(),
                builder: (_, snapshot) {
                  final data = snapshot.data;
                  return data != null ? _buildHeader(data) : const SizedBox.shrink();
                },
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimationLimiter(
              child: ListView.builder(
                itemCount: optionList.length,
                itemBuilder: (context, index) => AnimationConfiguration.staggeredList(
                  position: index,
                  duration: const Duration(milliseconds: 375),
                  child: ScaleAnimation(child: _buildSetting(optionList[index])),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, Map<String, String>> userImageInfo) {
    final userInfo = LocalStorage.instance.getUserInfo();
    String givenName = userInfo.givenName;
    String userMail = userInfo.userMail;
    final userImage = CachedNetworkImage(
      cacheManager: LocalStorage.instance.cacheManager,
      imageUrl: userImageInfo["url"]?["value"] ?? "",
      httpHeaders: userImageInfo["header"] ?? const <String, String>{},
      imageBuilder: (context, imageProvider) => CircleAvatar(radius: 40.0, backgroundImage: imageProvider),
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => const SpinKitRotatingCircle(color: Colors.white),
      errorWidget: (context, url, error) {
        Log.e(error.toString());
        return const Icon(Icons.error);
      },
    );
    final columnItem = <Widget>[];
    final data = MediaQuery.of(context);
    if (givenName.isNotEmpty) {
      columnItem
        ..add(Text(givenName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
        ..add(const SizedBox(height: 5.0))
        ..add(
          MediaQuery(
            data: data.copyWith(textScaler: TextScaler.noScaling),
            child: Text(userMail, style: const TextStyle(fontSize: 16)),
          ),
        );
    } else {
      givenName = (givenName.isEmpty) ? R.current.pleaseLogin : givenName;
      userMail = (userMail.isEmpty) ? "" : userMail;
    }
    final taskFlow = TaskFlow();
    final task = NTUTTask("ImageTask");
    task.openLoadingDialog = false;
    taskFlow.addTask(task);
    return Container(
      padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: InkWell(
              child: FutureBuilder<bool>(
                future: taskFlow.start(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done && snapshot.data == true) {
                    return userImage;
                  }
                  return SpinKitRotatingCircle(color: Theme.of(context).colorScheme.secondary);
                },
              ),
              onTap: () {
                LocalStorage.instance.cacheManager.emptyCache(); //清除圖片暫存
              },
            ),
          ),
          const SizedBox(width: 16.0),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: columnItem,
          ),
        ],
      ),
    );
  }

  Widget _buildSetting(Map<String, Object?> data) {
    return InkWell(
      onTap: () {
        final action = data['onPress'];
        if (action is OnListViewPress) _onListViewPress(action);
      },
      child: Container(
        padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(data['icon'] as IconData, color: data['color'] as Color?),
            const SizedBox(width: 20.0),
            Text(data['title']?.toString() ?? '', style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
