import 'package:flutter/material.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/file/file_download.dart';
import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/util/html_utils.dart';
import 'package:flutter_app/ui/other/list_view_animator.dart';
import 'package:flutter_app/ui/other/route_utils.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class IPlusAnnouncementDetailPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final CourseInfoJson courseInfo;

  const IPlusAnnouncementDetailPage(this.courseInfo, this.data, {super.key});

  @override
  State<IPlusAnnouncementDetailPage> createState() => _IPlusAnnouncementDetailPage();
}

class _IPlusAnnouncementDetailPage extends State<IPlusAnnouncementDetailPage> {

  bool addLink = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Get.back(),
        ),
        title: Text(widget.courseInfo.main.course.name),
        actions: <Widget>[
          PopupMenuButton<int>(
            onSelected: (result) {
              if (!addLink) {
                setState(() {
                  addLink = true;
                  widget.data["body"] = HtmlUtils.addLink(widget.data["body"]?.toString() ?? "");
                });
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 0,
                child: Text(R.current.identifyLinks),
              ),
            ],
          )
        ],
      ),
      body: SingleChildScrollView(
        child: _showAnnouncementDetail(),
      ),
    );
  }

  Widget _showAnnouncementDetail() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.data["title"]?.toString() ?? "",
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ],
              ),
              // 顯示格線
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(widget.data["sender"]?.toString() ?? ""),
                  ),
                  Expanded(
                    child: Text(
                      widget.data["postTime"]?.toString() ?? "",
                      textAlign: TextAlign.end,
                    ),
                  )
                ],
              ),
              Container(
                color: Colors.black12,
                height: 1,
              ),
              _showHtmlWidget(),
              _showFileList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _showFileList() {
    final rawFileMap = widget.data['file'];
    final Map<String, String> fileUrlMap = rawFileMap is Map
        ? rawFileMap.map((key, value) => MapEntry(key.toString(), value.toString()))
        : <String, String>{};
    final List<String> fileNameList = fileUrlMap.keys.toList(); //key : 文件名稱  value : 文件下載url
    if (fileNameList.isEmpty) {
      return Container(
        color: Colors.black12,
        height: 1,
      );
    } else {
      return Column(
        children: <Widget>[
          Container(
            color: Colors.black12,
            height: 1,
          ),
          Row(
            children: <Widget>[
              Text(
                R.current.file,
                textAlign: TextAlign.start,
              ),
            ],
          ),
          ListView.separated(
            shrinkWrap: true,
            itemCount: fileNameList.length,
            itemBuilder: (context, index) {
              final fileWidget = Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Row(
                  children: <Widget>[
                    Text(
                      fileNameList[index],
                      style: const TextStyle(fontSize: 15, color: Colors.blue),
                    )
                  ],
                ),
              );
              return InkWell(
                child: WidgetAnimator(fileWidget),
                onTap: () {
                  final url = fileUrlMap[fileNameList[index]];
                  if (url != null && url.isNotEmpty) {
                    _downloadFile(url, fileNameList[index]);
                  }
                },
              );
            },
            separatorBuilder: (context, index) {
              // 顯示格線
              return Container(
                color: Colors.black12,
                height: 1,
              );
            },
          ),
        ],
      );
    }
  }

  Widget _showHtmlWidget() {
    return HtmlWidget(
      widget.data["body"]?.toString() ?? "",
      onTapUrl: (url) {
        onUrlTap(url);
        return true;
      },
    );
  }

  void _downloadFile(String url, String name) async {
    String courseName = widget.courseInfo.main.course.name;
    await FileDownload.download(url, courseName, name);
  }

  void onUrlTap(String url) async {
    Log.d(url);
    if (Uri.parse(url).host.contains("istudy")) {
    } else {
      _launchURL(url);
    }
  }

  Future<void> _launchURL(String url) async {
    final preparedUrl = Uri.tryParse(url);
    if (preparedUrl != null && await canLaunchUrl(preparedUrl)) {
      RouteUtils.toWebViewPage(initialUrl: preparedUrl);
    } else {
      throw 'Could not launch $url';
    }
  }
}
