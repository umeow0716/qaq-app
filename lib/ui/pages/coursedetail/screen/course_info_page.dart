import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
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
import 'package:intl/intl.dart';
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
  static const _cacheMaxAge = Duration(days: 7);

  List<CourseStudent> _students = <CourseStudent>[];
  bool _isStudentLoading = true;
  bool _isStudentRefreshing = false;
  String? _studentError;
  DateTime? _studentLastUpdated;
  bool _isCourseExtraRefreshing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadCourseExtraInfo();
      _loadCourseStudents();
    });
  }

  Future<void> _loadCourseExtraInfo() async {
    final storage = LocalStorage.instance;
    final courseId = widget.courseInfo.main.course.id;
    final cached = storage.getCourseExtraInfoCache(courseId);

    if (cached != null && storage.hasCompleteCourseExtraInfoCache(courseId)) {
      // Render the cached authoritative counts immediately. A stale refresh
      // never clears or replaces them with a spinner.
      widget.courseInfo.extra = cached;
      if (mounted) {
        setState(() {});
      }

      final cachedAt = cached.courseExtraUpdatedAt;
      final isStale = cachedAt == null || DateTime.now().difference(cachedAt) > _cacheMaxAge;
      final autoVpnEnabled = storage.getOtherSetting().autoConnectIStudyVpn;
      if (isStale && autoVpnEnabled) {
        unawaited(_refreshCourseExtraInfo());
      }
      return;
    }

    await _refreshCourseExtraInfo();
  }

  Future<void> _refreshCourseExtraInfo() async {
    if (_isCourseExtraRefreshing) return;
    _isCourseExtraRefreshing = true;

    try {
      final courseId = widget.courseInfo.main.course.id;
      final task = CourseExtraInfoTask(courseId, forceRefresh: true)
        ..openLoadingDialog = false
        ..openErrorDialog = false;
      final taskFlow = TaskFlow()..addTask(task);

      bool success;
      try {
        success = await taskFlow.start();
      } catch (_) {
        success = false;
      }
      if (!success) return;

      final result = task.result;
      if (result != null && mounted) {
        setState(() {
          // The old numbers stay visible for the whole request. Once a fresh
          // authoritative snapshot arrives, swap them in atomically.
          widget.courseInfo.extra = result;
        });
      }
    } finally {
      _isCourseExtraRefreshing = false;
    }
  }

  void _manualRefreshCourseStudents() {
    // The student-list refresh is also the explicit refresh affordance for
    // the course-detail snapshot. These requests are independent: iStudy can
    // fail without touching the authoritative CourseExtra counts.
    unawaited(_refreshCourseExtraInfo());
    unawaited(_refreshCourseStudents(manual: true));
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
    final cached = LocalStorage.instance.getCourseExtraInfoCache(courseId);
    final cachedAt = cached?.classmateUpdatedAt;
    if (cached != null && cachedAt != null) {
      final cachedStudents = cached.classmate
          .map(
            (student) => CourseStudent(department: student.className, id: student.studentId, name: student.studentName),
          )
          .toList();
      if (mounted) {
        setState(() {
          _students = cachedStudents;
          _studentLastUpdated = cachedAt;
          _studentError = null;
          _isStudentLoading = false;
        });
      }

      final cacheAge = DateTime.now().difference(cachedAt);
      final autoVpnEnabled = LocalStorage.instance.getOtherSetting().autoConnectIStudyVpn;
      if (cacheAge > _cacheMaxAge && autoVpnEnabled) {
        unawaited(_refreshCourseStudents(manual: false));
      }
      return;
    }

    await _refreshCourseStudents(manual: false);
  }

  Future<void> _refreshCourseStudents({required bool manual}) async {
    if (LocalStorage.instance.getAccount() != widget.studentId) return;

    final hasCache = _studentLastUpdated != null;
    if (mounted) {
      setState(() {
        _isStudentRefreshing = true;
        if (!hasCache) {
          _isStudentLoading = true;
        }
        if (manual) {
          _studentError = null;
        }
      });
    }

    final courseId = widget.courseInfo.main.course.id;
    final task = IPlusGetStudentListTask(courseId: courseId)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final taskFlow = TaskFlow()..addTask(task);
    bool success;
    try {
      success = await taskFlow.start();
    } catch (_) {
      success = false;
    }
    final students = task.result;

    if (!success || students == null) {
      if (!mounted) return;
      setState(() {
        _isStudentLoading = false;
        _isStudentRefreshing = false;
        // A failed background refresh must not replace a usable cache with an
        // error. Manual refreshes intentionally surface the original iStudy
        // network/VPN message in the list area.
        if (manual || !hasCache) {
          _studentError = task.errorMessage ?? R.current.getStudentListError;
        }
      });
      return;
    }

    final departmentMap = students.isEmpty ? <String, String>{} : await _loadCourseDepartmentMap();
    final resolvedStudents = students
        .map(
          (student) => CourseStudent(
            department: student.department.isNotEmpty ? student.department : getDepartment(departmentMap, student.id),
            id: student.id,
            name: student.name,
          ),
        )
        .toList();
    final updatedAt = DateTime.now();

    final storage = LocalStorage.instance;
    storage.setCourseExtraInfoCache(
      courseId,
      CourseExtraInfoJson(
        classmate: resolvedStudents
            .map(
              (student) =>
                  ClassmateJson(className: student.department, studentId: student.id, studentName: student.name),
            )
            .toList(),
        classmateUpdatedAt: updatedAt,
      ),
    );
    await storage.saveCourseExtraInfoCache();

    if (!mounted) return;
    setState(() {
      _students = resolvedStudents;
      _studentLastUpdated = updatedAt;
      _studentError = null;
      _isStudentLoading = false;
      _isStudentRefreshing = false;
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
      _buildStudentListTitle(),
    ];

    if (_isStudentLoading) {
      // The title-row spinner is the single loading indicator for a cache miss.
      // Keep the list area empty so loading never blocks or duplicates the
      // cached student-table presentation.
      return listItem;
    }

    final studentError = _studentError;
    if (studentError != null) {
      listItem.add(
        _StudentListEntrance(
          key: ValueKey('student-error-$studentError'),
          rows: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(studentError, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      );
      return listItem;
    }

    if (_students.isNotEmpty) {
      final studentRows = <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildClassmateInfo(1, R.current.kDepartment, R.current.studentId, R.current.name, isHeader: true),
        ),
      ];

      for (int i = 0; i < _students.length; i++) {
        final student = _students[i];
        final studentName = student.name.isEmpty ? R.current.unknownStudent : student.name;
        final studentId = student.id;
        final department = student.department.isNotEmpty ? student.department : R.current.unknownDepartment;
        studentRows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildClassmateInfo(i, department, studentId, studentName),
          ),
        );
      }

      listItem.add(_buildAnimatedStudentList(studentRows));
    }

    return listItem;
  }

  Widget _buildAnimatedStudentList(List<Widget> rows) {
    final revision = _studentLastUpdated?.microsecondsSinceEpoch ?? 0;
    return _StudentListEntrance(key: ValueKey('student-list-$revision'), rows: rows);
  }

  List<Widget> _buildCourseData() {
    final courseMainInfo = widget.courseInfo.main;
    final courseExtraInfo = widget.courseInfo.extra;
    final courseData = <Widget>[
      _buildCourseInfo(sprintf('%s: %s', [R.current.courseId, courseMainInfo.course.id])),
      _buildCourseInfo(sprintf('%s: %s', [R.current.courseName, courseMainInfo.course.name])),
      _buildCourseInfo(sprintf('%s: %s    ', [R.current.credit, courseMainInfo.course.credits])),
      _buildCourseInfo(sprintf('%s: %s    ', [R.current.category, courseExtraInfo.course.category])),
    ];

    final selectNumber = courseExtraInfo.course.selectNumber.trim();
    final withdrawNumber = courseExtraInfo.course.withdrawNumber.trim();
    courseData.add(
      _buildCourseInfo(
        sprintf('%s: %s', [R.current.numberOfStudent, _isAuthoritativeCourseCount(selectNumber) ? selectNumber : '']),
      ),
    );
    courseData.add(
      _buildCourseInfo(
        sprintf('%s: %s', [
          R.current.numberOfWithdraw,
          _isAuthoritativeCourseCount(withdrawNumber) ? withdrawNumber : '',
        ]),
      ),
    );

    courseData.addAll([
      _buildCourseInfo(sprintf('%s: %s', [R.current.startClass, courseMainInfo.getOpenClassName()])),
      _buildCourseInfoWithButton(
        sprintf('%s: %s', [R.current.instructor, courseMainInfo.getTeacherName()]),
        R.current.syllabus,
        courseMainInfo.course.scheduleHref,
      ),
      _buildMultiButtonInfo(
        sprintf('%s: ', [R.current.classroom]),
        R.current.classroomUse,
        courseMainInfo.getClassroomNameList(),
        courseMainInfo.getClassroomHrefList(),
      ),
    ]);

    return courseData;
  }

  bool _isAuthoritativeCourseCount(String value) => int.tryParse(value.trim()) != null;

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

  Widget _buildStudentListTitle() {
    const titleStyle = TextStyle(fontSize: 24);
    final updatedAt = _studentLastUpdated;
    final canRefresh = LocalStorage.instance.getAccount() == widget.studentId;
    final showSpinner = _isStudentLoading || _isStudentRefreshing;

    return Container(
      padding: const EdgeInsets.only(top: 5, bottom: 5),
      child: Row(
        children: <Widget>[
          Text(R.current.studentList, style: titleStyle),
          if (showSpinner) ...[
            const SizedBox(width: 2),
            const SizedBox(
              width: 36,
              height: 36,
              child: Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
          const SizedBox(width: 2),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: R.current.refresh,
              onPressed: canRefresh && !_isStudentLoading && !_isStudentRefreshing
                  ? _manualRefreshCourseStudents
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (updatedAt != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    "${R.current.lastUpdated}: ${DateFormat('yyyy-MM-dd HH:mm').format(updatedAt)}",
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
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

class _StudentListEntrance extends StatefulWidget {
  const _StudentListEntrance({super.key, required this.rows});

  final List<Widget> rows;

  @override
  State<_StudentListEntrance> createState() => _StudentListEntranceState();
}

class _StudentListEntranceState extends State<_StudentListEntrance> with SingleTickerProviderStateMixin {
  static const _rowDuration = Duration(milliseconds: 375);
  static const _rowDelay = Duration(milliseconds: 62);
  static const _verticalOffset = 50.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final rowCount = widget.rows.length;
    final totalMilliseconds = rowCount <= 1
        ? _rowDuration.inMilliseconds
        : _rowDuration.inMilliseconds + ((rowCount - 1) * _rowDelay.inMilliseconds);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMilliseconds),
    );

    // Keep the very first painted frame at progress 0. Async-loaded rows are
    // inserted after the page's outer AnimationLimiter has already finished;
    // starting here in initState can let layout and animation advance before
    // the first visible frame. Starting after that first frame guarantees the
    // list visibly enters instead of flashing directly into its final state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMilliseconds = _controller.duration!.inMilliseconds.toDouble();
    return Column(
      children: List<Widget>.generate(widget.rows.length, (index) {
        final startMilliseconds = (index * _rowDelay.inMilliseconds).toDouble();
        final endMilliseconds = startMilliseconds + _rowDuration.inMilliseconds;
        final start = startMilliseconds / totalMilliseconds;
        final end = endMilliseconds / totalMilliseconds;

        return AnimatedBuilder(
          animation: _controller,
          child: widget.rows[index],
          builder: (context, child) {
            final progress = Interval(start, end, curve: Curves.ease).transform(_controller.value);
            // Unlike the static course rows, this list is inserted after an
            // async request. Animate layout height as well as paint so the full
            // table does not occupy its final height in a single frame.
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: progress,
                child: Opacity(
                  opacity: progress,
                  child: Transform.translate(offset: Offset(0, _verticalOffset * (1 - progress)), child: child),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
