import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/model/course/course_student.dart';
import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:flutter_app/src/task/course/course_department_map_task.dart';
import 'package:flutter_app/src/task/course/course_extra_info_task.dart';
import 'package:flutter_app/src/task/iplus/iplus_get_course_student_list_task.dart';
import 'package:flutter_app/src/task/task_flow.dart';
import 'package:flutter_app/ui/other/route_utils.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:sprintf/sprintf.dart';

class CourseInfoPage extends StatefulWidget {
  final CourseInfoJson courseInfo;
  final String studentId;

  const CourseInfoPage(this.studentId, this.courseInfo, {super.key});

  final int courseInfoWithAlpha = 0x44;

  @override
  State<CourseInfoPage> createState() => _CourseInfoPageState();
}

class _CourseInfoPageState extends State<CourseInfoPage> with AutomaticKeepAliveClientMixin {
  List<CourseStudent> _students = <CourseStudent>[];
  Map<String, String> _departmentMap = <String, String>{};
  bool _isStudentLoading = true;
  String? _studentError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadCourseExtraInfo();
      _loadCourseStudents();
    });
  }

  Future<void> _loadCourseExtraInfo() async {
    final courseId = widget.courseInfo.main.course.id;
    final task = CourseExtraInfoTask(courseId)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);

    if (await taskFlow.start()) {
      final result = task.result;
      if (result != null) {
        widget.courseInfo.extra = result;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Future<void> _loadCourseStudents() async {
    if (LocalStorage.instance.getAccount() != widget.studentId) {
      if (mounted) {
        setState(() {
          _isStudentLoading = false;
          _studentError = R.current.notSupport;
        });
      }
      return;
    }

    final courseId = widget.courseInfo.main.course.id;
    final task = IPlusGetStudentListTask(courseId: courseId)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);
    final success = await taskFlow.start();
    final students = task.result;

    if (!success || students == null) {
      if (mounted) {
        setState(() {
          _isStudentLoading = false;
          _studentError = task.errorMessage ?? R.current.getStudentListError;
        });
      }
      return;
    }

    final departmentMap = students.isEmpty ? <String, String>{} : await _loadCourseDepartmentMap();
    if (!mounted) return;

    setState(() {
      _students = students;
      _departmentMap = departmentMap;
      _studentError = null;
      _isStudentLoading = false;
    });
  }

  Future<Map<String, String>> _loadCourseDepartmentMap() async {
    final semester = widget.courseInfo.extra.courseSemester;
    final task = CourseDepartmentMapTask(year: semester.year, semester: semester.semester)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);

    if (await taskFlow.start()) {
      return task.result ?? <String, String>{};
    }
    return <String, String>{};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(padding: const EdgeInsets.only(top: 20), child: _buildAnimationList());
  }

  Widget _buildAnimationList() {
    final listItem = _buildListItems();
    return AnimationLimiter(
      child: ListView.builder(
        itemCount: listItem.length,
        itemBuilder: (BuildContext context, int index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: Container(padding: const EdgeInsets.only(left: 20, right: 20), child: listItem[index]),
                  onTap: () {},
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildListItems() {
    final listItem = <Widget>[
      _buildInfoTitle(R.current.courseData),
      ..._buildCourseData(),
      _buildInfoTitle(''),
      _buildInfoTitle(R.current.studentList),
    ];

    if (_isStudentLoading) {
      listItem.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return listItem;
    }

    final studentError = _studentError;
    if (studentError != null) {
      listItem.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(studentError, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
      return listItem;
    }

    if (_students.isNotEmpty) {
      listItem.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildClassmateInfo(1, R.current.kDepartment, R.current.studentId, R.current.name, isHeader: true),
        ),
      );

      for (int i = 0; i < _students.length; i++) {
        final student = _students[i];
        final studentName = student.name.isEmpty ? R.current.unknownStudent : student.name;
        final studentId = student.id;
        final department = getDepartment(_departmentMap, studentId);
        listItem.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildClassmateInfo(i, department, studentId, studentName),
          ),
        );
      }
    }

    return listItem;
  }

  List<Widget> _buildCourseData() {
    final courseMainInfo = widget.courseInfo.main;
    final courseExtraInfo = widget.courseInfo.extra;
    final courseData = <Widget>[
      _buildCourseInfo(sprintf('%s: %s', [R.current.courseId, courseMainInfo.course.id])),
      _buildCourseInfo(sprintf('%s: %s', [R.current.courseName, courseMainInfo.course.name])),
      _buildCourseInfo(sprintf('%s: %s    ', [R.current.credit, courseMainInfo.course.credits])),
      _buildCourseInfo(sprintf('%s: %s    ', [R.current.category, courseExtraInfo.course.category])),
      _buildCourseInfoWithButton(
        sprintf('%s: %s', [R.current.instructor, courseMainInfo.getTeacherName()]),
        R.current.syllabus,
        courseMainInfo.course.scheduleHref,
      ),
      _buildCourseInfo(sprintf('%s: %s', [R.current.startClass, courseMainInfo.getOpenClassName()])),
      _buildMultiButtonInfo(
        sprintf('%s: ', [R.current.classroom]),
        R.current.classroomUse,
        courseMainInfo.getClassroomNameList(),
        courseMainInfo.getClassroomHrefList(),
      ),
    ];

    if (!_isStudentLoading && _studentError == null) {
      courseData.add(_buildCourseInfo(sprintf('%s: %s', [R.current.numberOfStudent, _students.length])));
    }

    return courseData;
  }

  Widget _buildCourseInfo(String text) {
    const textStyle = TextStyle(fontSize: 18);
    return Container(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: <Widget>[
          const Icon(Icons.details),
          Expanded(child: Text(text, style: textStyle)),
        ],
      ),
    );
  }

  void _launchWebView(String title, String urlString) {
    final url = Uri.tryParse(urlString);

    if (url != null) {
      RouteUtils.toWebViewPage(initialUrl: url, title: title);
    } else {
      // TODO: handle exceptions when the url is null. (null means it may caused by the parse process error.)
    }
  }

  String getDepartment(Map<String, String> departmentMap, String studentId) {
    /*
      * Since we don't have official data to describe the following hard-coded rule is correct.
      * It may need to confirm or just leave it.
      */
    if (studentId.substring(0, 1) == '4') {
      return R.current.nationalTaipeiUniversity;
    }

    if (studentId.substring(0, 1) == 'B') {
      return R.current.taipeiMedicineUniversity;
    }

    if (studentId.substring(3, 6) == '054') {
      return R.current.aduit;
    }

    String? department = departmentMap[studentId.substring(3, 5)];

    if (department != null) {
      return department;
    }

    department = departmentMap[studentId.substring(3, 6)];

    if (department != null) {
      return department;
    }

    return R.current.unknownDepartment;
  }

  Widget _buildClassmateInfo(
    int index,
    String departmentName,
    String studentId,
    String studentName, {
    bool isHeader = false,
  }) {
    final height = isHeader ? 25.0 : 50.0;

    final color = (index % 2 == 1)
        ? Theme.of(context).colorScheme.surface
        : Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(widget.courseInfoWithAlpha);
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          SizedBox(width: 4, height: height),
          Expanded(child: Text(departmentName, textAlign: TextAlign.center)),
          SizedBox(width: 4, height: height),
          Expanded(child: Text(studentId, textAlign: TextAlign.center)),
          SizedBox(width: 4, height: height),
          Expanded(child: Text(studentName, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildCourseInfoWithButton(String text, String buttonText, String url) {
    return Container(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          const Icon(Icons.details),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18))),
          (url.isNotEmpty)
              ? ElevatedButton(child: Text(buttonText), onPressed: () => _launchWebView(buttonText, url))
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildInfoTitle(String title) {
    const textStyle = TextStyle(fontSize: 24);
    return Container(
      padding: const EdgeInsets.only(top: 5, bottom: 5),
      child: Row(children: <Widget>[Text(title, style: textStyle)]),
    );
  }

  Widget _buildMultiButtonInfo(String title, String buttonText, List<String> textList, List<String> urlList) {
    const textStyle = TextStyle(fontSize: 18);
    final classroomItemList = <Widget>[];

    for (int i = 0; i < textList.length; i++) {
      final text = textList[i];
      classroomItemList.add(
        FittedBox(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(text, style: textStyle),
              const SizedBox(width: 4),
              urlList[i].isNotEmpty
                  ? FittedBox(
                      child: ElevatedButton(
                        onPressed: () => _launchWebView(buttonText, urlList[i]),
                        child: Text(buttonText),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.details),
              Text(title, style: textStyle),
            ],
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: classroomItemList),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
