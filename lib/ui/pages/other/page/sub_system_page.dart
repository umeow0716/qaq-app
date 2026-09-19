import 'package:flutter/material.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/model/ntut/ap_tree_json.dart';
import 'package:qaq_app/src/task/ntut/ntut_sub_system_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/ui/other/route_utils.dart';

class SubSystemPage extends StatefulWidget {
  final String title;
  final String? arg;

  const SubSystemPage({super.key, required this.title, this.arg});

  @override
  State<SubSystemPage> createState() => _SubSystemPageState();
}

class _SubSystemPageState extends State<SubSystemPage> {
  bool isLoading = true;
  APTreeJson? apTree;

  @override
  void initState() {
    super.initState();
    loadTree(widget.arg);
  }

  void loadTree(String? arg) async {
    setState(() {
      isLoading = true;
    });
    TaskFlow taskFlow = TaskFlow();
    var task = NTUTSubSystemTask(arg);
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      apTree = task.result;
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: isLoading ? const Center(child: CircularProgressIndicator()) : buildTree(),
    );
  }

  Widget buildTree() {
    final tree = apTree;
    if (tree == null) return const SizedBox.shrink();
    return ListView.builder(
      shrinkWrap: true,
      itemCount: tree.apList.length,
      itemBuilder: (BuildContext context, int index) {
        final ap = tree.apList[index];
        return InkWell(
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                Expanded(flex: 1, child: Icon((ap.type == 'link') ? Icons.link_outlined : Icons.folder_outlined)),
                Expanded(flex: 8, child: Text(ap.description)),
              ],
            ),
          ),
          onTap: () async {
            if (ap.type == 'link') {
              // This step checks if the `ap.urlLink` is a completed url (should has scheme).
              // Because we don't need to add any prefix such as `NTUTConnector.host` when it is a completed url.
              final apLinkUrl = Uri.tryParse(ap.urlLink);
              if (apLinkUrl != null && apLinkUrl.hasScheme) {
                RouteUtils.toWebViewPage(initialUrl: apLinkUrl, title: ap.description, shouldUseAppCookies: true);
                return;
              }

              final urlString = "${NTUTConnector.host}${ap.urlLink}";
              final url = Uri.tryParse(urlString);

              if (url != null) {
                RouteUtils.toWebViewPage(initialUrl: url, title: ap.description, shouldUseAppCookies: true);
              } else {
                // TODO: handle exceptions when the url is null. (null means it may caused by the parse process error.)
              }
            } else {
              RouteUtils.toSubSystemPage(ap.description, ap.apDn);
            }
          },
        );
      },
    );
  }
}
