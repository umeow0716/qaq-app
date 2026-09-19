import 'package:flutter/material.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/model/ischoolplus/ischool_plus_announcement_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/task/iplus/iplus_course_announcement_detail_task.dart';
import 'package:qaq_app/src/task/iplus/iplus_course_announcement_task.dart';
import 'package:qaq_app/src/task/iplus/iplus_get_course_subscribe_task.dart';
import 'package:qaq_app/src/task/iplus/iplus_set_course_subscribe_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/ui/other/route_utils.dart';

class IPlusAnnouncementPage extends StatefulWidget {
  final CourseInfoJson courseInfo;
  final String studentId;

  const IPlusAnnouncementPage(this.studentId, this.courseInfo, {super.key});

  @override
  State<IPlusAnnouncementPage> createState() => _IPlusAnnouncementPage();
}

class _IPlusAnnouncementPage extends State<IPlusAnnouncementPage> with AutomaticKeepAliveClientMixin {
  List<ISchoolPlusAnnouncementJson> items = <ISchoolPlusAnnouncementJson>[];
  String courseBid = '';
  bool isSupport = false;
  bool openNotifications = false;
  bool _isLoading = true;
  bool _isOpeningAnnouncement = false;
  bool _isUpdatingSubscription = false;
  String? _loadError;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    isSupport = LocalStorage.instance.getAccount() == widget.studentId;
    if (isSupport) {
      _loadAnnouncements();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadAnnouncements() async {
    final courseId = widget.courseInfo.main.course.id;
    final task = IPlusCourseAnnouncementTask(courseId)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);
    final success = await taskFlow.start();
    final result = task.result;

    if (!mounted) return;

    if (!success || result == null) {
      setState(() {
        items = <ISchoolPlusAnnouncementJson>[];
        _isLoading = false;
        _loadError = task.errorMessage ?? R.current.getISchoolPlusCourseAnnouncementError;
      });
      return;
    }

    setState(() {
      items = result;
      _isLoading = false;
      _loadError = null;
    });

    _loadSubscription(courseId);
  }

  Future<void> _loadSubscription(String courseId) async {
    final task = IPlusGetCourseSubscribeTask(courseId)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);
    await taskFlow.start();
    final result = task.result;

    if (!mounted || result == null) return;

    setState(() {
      courseBid = result['courseBid']?.toString() ?? '';
      openNotifications = result['openNotifications'] == true;
    });
  }

  Future<void> _getAnnouncementDetail(ISchoolPlusAnnouncementJson value) async {
    if (_isOpeningAnnouncement) return;

    setState(() {
      _isOpeningAnnouncement = true;
      _actionError = null;
    });

    final task = IPlusCourseAnnouncementDetailTask(value)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);
    final success = await taskFlow.start();
    final detail = task.result;

    if (!mounted) return;

    setState(() {
      _isOpeningAnnouncement = false;
      if (!success || detail == null) {
        _actionError = task.errorMessage ?? R.current.unknownServerError;
      }
    });

    if (success && detail != null) {
      RouteUtils.toIPlusAnnouncementDetailPage(widget.courseInfo, Map<String, dynamic>.from(detail));
    }
  }

  Future<void> _toggleSubscription() async {
    if (_isUpdatingSubscription || courseBid.isEmpty) return;

    setState(() {
      _isUpdatingSubscription = true;
      _actionError = null;
    });

    final task = IPlusSetCourseSubscribeTask(courseBid, !openNotifications)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);
    final success = await taskFlow.start();

    if (!mounted) return;

    setState(() {
      _isUpdatingSubscription = false;
      if (success && task.result == true) {
        openNotifications = !openNotifications;
      } else {
        _actionError = task.errorMessage ?? R.current.unknownServerError;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final actionError = _actionError;
    return Scaffold(
      body: Column(
        children: [
          if (_isOpeningAnnouncement) const LinearProgressIndicator(),
          if (actionError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                actionError,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: isSupport && courseBid.isNotEmpty
          ? FloatingActionButton(
              onPressed: _isUpdatingSubscription ? null : _toggleSubscription,
              tooltip: R.current.subscribe,
              child: _isUpdatingSubscription
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : openNotifications
                  ? const Icon(Icons.notifications_active)
                  : const Icon(Icons.notifications_off),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (!isSupport) {
      return Center(child: Text(R.current.notSupport));
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final loadError = _loadError;
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(loadError, textAlign: TextAlign.center),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(child: Text(R.current.noAnyAnnouncement));
    }

    return _buildMailList();
  }

  Widget _buildMailList() {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, index) {
        return InkWell(onTap: () => _getAnnouncementDetail(items[index]), child: _listItem(items[index]));
      },
    );
  }

  Widget _listItem(ISchoolPlusAnnouncementJson data) {
    final fontWeight = data.readflag != 1 ? FontWeight.bold : FontWeight.normal;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 5, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.account_circle, size: 55, color: Colors.red),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              data.subject,
                              overflow: TextOverflow.visible,
                              style: TextStyle(fontWeight: fontWeight, fontSize: 17),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(data.realname, style: TextStyle(fontWeight: fontWeight, fontSize: 15.5)),
                          Text(data.postdate, style: TextStyle(fontWeight: fontWeight, fontSize: 13.5)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}
