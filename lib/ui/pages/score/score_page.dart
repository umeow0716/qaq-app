import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/config/app_colors.dart';
import 'package:qaq_app/src/connector/core/network_request_pool.dart';
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/course/course_main_extra_json.dart';
import 'package:qaq_app/src/model/course/course_score_json.dart';
import 'package:qaq_app/src/model/course/course_syllabus_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/task/course/course_system_task.dart';
import 'package:qaq_app/src/task/score/score_rank_task.dart';
import 'package:qaq_app/src/task/task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/ui/other/app_expansion_tile.dart';
import 'package:qaq_app/ui/other/my_toast.dart';
import 'package:qaq_app/ui/other/progress_rate_dialog.dart';
import 'package:qaq_app/ui/pages/score/app_bar_action_buttons.dart';
import 'package:qaq_app/ui/pages/score/course_score_section.dart';
import 'package:qaq_app/ui/pages/score/graduation_picker.dart';
import 'package:qaq_app/ui/pages/score/rank_grade_metrics.dart';
import 'package:qaq_app/ui/pages/score/semester_score_grade_metrics.dart';
import 'package:qaq_app/ui/pages/score/widgets/calculation_warning_widget.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

class ScoreViewerPage extends StatefulWidget {
  const ScoreViewerPage({super.key});

  @override
  State<ScoreViewerPage> createState() => _ScoreViewerPageState();
}

class _ScoreViewerPageState extends State<ScoreViewerPage> with TickerProviderStateMixin {
  static bool appExpansionInitiallyExpanded = false;

  TabController? _tabController;
  final CourseScoreCreditJson courseScoreCredit = LocalStorage.instance.getCourseScoreCredit();

  final List<SemesterCourseScoreJson> courseScoreList = [];
  final ScrollController _scrollController = ScrollController();
  final List<Widget> tabLabelList = [];
  final List<Widget> tabChildList = [];
  final List<String> _desktopSectionLabels = [];

  int _currentTabIndex = 0;
  bool _isLoading = true;
  double? _desktopProgress;
  String? _desktopProgressText;

  Widget get _summaryTile {
    final titleWidget = _buildTile(
      sprintf("%s %d/%d", [
        R.current.creditSummary,
        courseScoreCredit.getTotalCourseCredit(),
        courseScoreCredit.graduationInformation.lowCredit,
      ]),
    );

    final widgetList = [
      _buildType(constCourseType[0], R.current.compulsoryCompulsory),
      _buildType(constCourseType[1], R.current.revisedCommonCompulsory),
      _buildType(constCourseType[2], R.current.jointElective),
      _buildType(constCourseType[3], R.current.compulsoryProfessional),
      _buildType(constCourseType[4], R.current.compulsoryMajorRevision),
      _buildType(constCourseType[5], R.current.professionalElectives),
    ];

    return AppExpansionTile(title: titleWidget, initiallyExpanded: appExpansionInitiallyExpanded, children: widgetList);
  }

  Widget get _generalLessonItemTile {
    final generalLesson = courseScoreCredit.getGeneralLesson();
    final List<Widget> widgetList = [];
    int selectCredit = 0;
    int coreCredit = 0;

    for (final courseScoreInfoList in generalLesson.values) {
      for (final course in courseScoreInfoList) {
        if (course.isCoreGeneralLesson) {
          coreCredit += course.credit.toInt();
        } else {
          selectCredit += course.credit.toInt();
        }

        final courseItemWidget = _buildOneLineCourse(course.name, course.openClass);
        widgetList.add(courseItemWidget);
      }
    }

    final titleWidget = _buildTile(
      sprintf("%s\n%s: %d %s: %d", [
        R.current.generalLessonSummary,
        R.current.takeCore,
        coreCredit,
        R.current.takeSelect,
        selectCredit,
      ]),
    );

    return AppExpansionTile(title: titleWidget, initiallyExpanded: appExpansionInitiallyExpanded, children: widgetList);
  }

  Widget get _otherDepartmentItemTile {
    final department = LocalStorage.instance.getGraduationInformation().selectDepartment.substring(0, 2);
    final otherDepartmentMaxCredit = courseScoreCredit.graduationInformation.outerDepartmentMaxCredit;

    final generalLesson = courseScoreCredit.getOtherDepartmentCourse(department);
    final List<Widget> widgetList = [];
    int otherDepartmentCredit = 0;

    for (final courseScoreInfoList in generalLesson.values) {
      for (final course in courseScoreInfoList) {
        otherDepartmentCredit += course.credit.toInt();
        final courseItemWidget = _buildOneLineCourse(course.name, course.openClass);
        widgetList.add(courseItemWidget);
      }
    }

    final titleWidget = _buildTile(
      sprintf("%s: %d  %s: %d", [
        R.current.takeForeignDepartmentCredits,
        otherDepartmentCredit,
        R.current.takeForeignDepartmentCreditsLimit,
        otherDepartmentMaxCredit,
      ]),
    );

    return AppExpansionTile(title: titleWidget, initiallyExpanded: appExpansionInitiallyExpanded, children: widgetList);
  }

  @override
  void initState() {
    super.initState();

    courseScoreList.addAll(LocalStorage.instance.getSemesterCourseScore());

    if (courseScoreList.isEmpty) {
      _addScoreRankTask();
    } else {
      _buildTabBar();
      setState(() => _isLoading = false);
    }
  }

  void _applyCourseCategory(String courseId, {required String category, required String openClass}) {
    for (final semesterScore in courseScoreList) {
      for (final courseInfo in semesterScore.courseScoreList) {
        if (courseInfo.courseId != courseId) continue;
        courseInfo.category = category;
        courseInfo.openClass = openClass;
      }
    }
  }

  Future<void> _populateCourseCategories() async {
    final storage = LocalStorage.instance;
    final missingCourseIds = <String>{};

    for (final semesterScore in courseScoreList) {
      for (final courseInfo in semesterScore.courseScoreList) {
        final courseId = courseInfo.courseId;
        if (courseId.isEmpty) continue;

        final cached = storage.getCourseExtraInfoCache(courseId);
        if (courseInfo.category.isNotEmpty) {
          storage.setCourseExtraInfoCache(
            courseId,
            CourseExtraInfoJson(
              courseSemester: semesterScore.semester,
              course: CourseExtraJson(
                id: courseId,
                name: courseInfo.nameZh.isNotEmpty ? courseInfo.nameZh : courseInfo.nameEn,
                category: courseInfo.category,
                openClass: courseInfo.openClass,
              ),
            ),
          );
          continue;
        }

        if (cached != null && cached.course.category.isNotEmpty) {
          courseInfo.category = cached.course.category;
          courseInfo.openClass = cached.course.openClass;
          storage.setCourseExtraInfoCache(
            courseId,
            CourseExtraInfoJson(
              courseSemester: semesterScore.semester,
              course: CourseExtraJson(
                id: courseId,
                name: courseInfo.nameZh.isNotEmpty ? courseInfo.nameZh : courseInfo.nameEn,
                category: cached.course.category,
                openClass: cached.course.openClass,
              ),
            ),
          );
          continue;
        }

        missingCourseIds.add(courseId);
      }
    }

    if (missingCourseIds.isEmpty) {
      await storage.saveCourseExtraInfoCache();
      return;
    }

    if (!mounted) return;

    final courseIds = missingCourseIds.toList(growable: false);
    final total = courseIds.length;
    int rate = 0;
    final progressRateDialog = _isDesktop ? null : ProgressRateDialog(context);

    if (_isDesktop) {
      setState(() {
        _desktopProgress = 0;
        _desktopProgressText = sprintf("%d/%d", [0, total]);
      });
    } else {
      progressRateDialog!.update(
        message: R.current.searchingCredit,
        nowProgress: 0,
        progressString: sprintf("%d/%d", [0, total]),
      );
      await progressRateDialog.show();
    }

    // Authenticate once before parallelizing course-system requests. Running
    // CourseSystemTask.execute() concurrently would race its shared login state
    // and could start multiple SSO logins at once.
    final sessionTask = CourseSystemTask<void>('CourseCategoryBatch')..openLoadingDialog = false;
    final sessionStatus = await sessionTask.execute();
    if (sessionStatus != TaskStatus.success) {
      if (_isDesktop) {
        if (mounted) {
          setState(() {
            _desktopProgress = null;
            _desktopProgressText = null;
          });
        }
      } else {
        await progressRateDialog!.hide();
      }
      return;
    }

    await NetworkRequestPool.shared.run<CourseSyllabusJson>(
      courseIds.map(
        (courseId) =>
            (timeout) => CourseConnector.getCourseCategory(courseId, timeout: timeout),
      ),
      shouldRetry: (result) => result == null || result.courseId.isEmpty || result.category.isEmpty,
      onComplete: (index, result) {
        rate++;
        if (_isDesktop) {
          if (mounted) {
            setState(() {
              _desktopProgress = rate / total;
              _desktopProgressText = sprintf("%d/%d", [rate, total]);
            });
          }
        } else {
          progressRateDialog!.update(nowProgress: rate / total, progressString: sprintf("%d/%d", [rate, total]));
        }

        if (result == null || result.category.isEmpty) return;
        final courseId = courseIds[index];
        _applyCourseCategory(courseId, category: result.category, openClass: result.className);
        storage.setCourseExtraInfoCache(
          courseId,
          CourseExtraInfoJson(
            courseExtraUpdatedAt: DateTime.now(),
            courseSemester: SemesterJson(
              year: result.year > 0 ? result.year.toString() : null,
              semester: result.semester > 0 ? result.semester.toString() : null,
            ),
            course: CourseExtraJson(
              id: result.courseId.isNotEmpty ? result.courseId : courseId,
              name: result.courseName,
              category: result.category,
              openClass: result.className,
              selectNumber: result.applyStudentCount.toString(),
              withdrawNumber: result.withdrawStudentCount.toString(),
            ),
          ),
        );
      },
    );
    await storage.saveCourseExtraInfoCache();
    if (_isDesktop) {
      if (mounted) {
        setState(() {
          _desktopProgress = null;
          _desktopProgressText = null;
        });
      }
    } else {
      await progressRateDialog!.hide();
    }
  }

  void _addScoreRankTask() async {
    final preserveDesktopContent = _isDesktop && courseScoreList.isNotEmpty;
    if (!preserveDesktopContent) {
      courseScoreList.clear();
    }

    setState(() => _isLoading = true);

    final scoreTaskFlow = TaskFlow();
    final scoreTask = ScoreRankTask()..openLoadingDialog = !_isDesktop;
    scoreTaskFlow.addTask(scoreTask);

    if (await scoreTaskFlow.start()) {
      final result = scoreTask.result;
      if (result != null) {
        courseScoreList
          ..clear()
          ..addAll(result);
      }
    }

    if (courseScoreList.isNotEmpty) {
      await _populateCourseCategories();
      await LocalStorage.instance.setSemesterCourseScore(courseScoreList);
    } else {
      MyToast.show(R.current.searchCreditIsNullWarning);
    }

    _buildTabBar();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onSelectFinish(GraduationInformationJson? value) {
    Log.d(value.toString());
    if (value != null) {
      courseScoreCredit.graduationInformation = value;
      LocalStorage.instance.setCourseScoreCredit(courseScoreCredit);
      LocalStorage.instance.saveCourseScoreCredit();
    }
    _buildTabBar();
  }

  void _addSearchCourseTypeTask() async {
    GraduationPicker picker = GraduationPicker(context);
    picker.show(_onSelectFinish);
    _buildTabBar();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  bool get _isDesktop => Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) return _buildDesktop(context);

    return DefaultTabController(
      length: tabLabelList.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(R.current.searchScore),
          actions: [
            ScorePageAppBarActionButtons(
              onRefreshPressed: _addScoreRankTask,
              onCalculateCreditPressed: _addSearchCourseTypeTask,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.mainColor,
            unselectedLabelColor: Colors.white,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            isScrollable: true,
            tabs: tabLabelList,
            onTap: (int index) {
              setState(() => _currentTabIndex = index);
            },
          ),
        ),
        body: SingleChildScrollView(
          child: (_isLoading || tabChildList.isEmpty) ? const SizedBox.shrink() : tabChildList[_currentTabIndex],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (tabChildList.isEmpty) {
      return const Center(child: _DesktopScoreLoadingBadge());
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                const Spacer(),
                ScorePageAppBarActionButtons(
                  onRefreshPressed: _addScoreRankTask,
                  onCalculateCreditPressed: _addSearchCourseTypeTask,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 172,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: _desktopSectionLabels.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final selected = _currentTabIndex == index;
                        return Material(
                          color: selected ? colorScheme.primaryContainer : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _currentTabIndex = index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              child: Text(
                                _desktopSectionLabels[index],
                                style: TextStyle(
                                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                  color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: tabChildList[_currentTabIndex],
                          ),
                        ),
                        if (_isLoading || _desktopProgress != null)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: _DesktopScoreLoadingBadge(progress: _desktopProgress, label: _desktopProgressText),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _buildTabBar() {
    tabLabelList.clear();
    tabChildList.clear();
    _desktopSectionLabels.clear();

    try {
      if (courseScoreCredit.graduationInformation.isSelect) {
        tabLabelList.add(_buildTabLabel(R.current.creditSummary));
        _desktopSectionLabels.add(R.current.creditSummary);
        final summaryChildren = <Widget>[
          _summaryTile,
          _generalLessonItemTile,
          _otherDepartmentItemTile,
          const ScoreCalculationWarning(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(R.current.courseDisclaimer, style: const TextStyle(fontSize: 14, color: Colors.redAccent)),
          ),
        ];
        tabChildList.add(
          _isDesktop
              ? Column(children: summaryChildren)
              : AnimationLimiter(
                  child: Column(
                    children: AnimationConfiguration.toStaggeredList(
                      childAnimationBuilder: (widget) =>
                          SlideAnimation(verticalOffset: 50.0, child: FadeInAnimation(child: widget)),
                      children: summaryChildren,
                    ),
                  ),
                ),
        );
      }
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
    }

    for (int i = 0; i < courseScoreList.length; i++) {
      final courseScore = courseScoreList[i];
      final semesterLabel = "${courseScore.semester.year}-${courseScore.semester.semester}";
      tabLabelList.add(_buildTabLabel(semesterLabel));
      _desktopSectionLabels.add(semesterLabel);
      tabChildList.add(_buildSemesterScores(courseScore));
    }

    if (_tabController != null) {
      if (tabChildList.length != _tabController?.length) {
        _tabController?.dispose();
        _tabController = TabController(length: tabChildList.length, vsync: this);
      }
    } else {
      _tabController = TabController(length: tabChildList.length, vsync: this);
    }

    _currentTabIndex = 0;
    _tabController?.animateTo(_currentTabIndex);
    setState(() {});
  }

  Widget _buildTabLabel(String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Tab(text: title),
  );

  Widget _buildTile(String title) => Container(
    height: 60,
    width: 300,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(width: 2, color: Theme.of(context).colorScheme.tertiary),
    ),
    child: Center(child: Text(title, textAlign: TextAlign.center)),
  );

  Widget _buildType(String type, String title) {
    final nowCredit = courseScoreCredit.getCreditByType(type);
    final minCredit = courseScoreCredit.graduationInformation.courseTypeMinCredit[type];

    return InkWell(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            Expanded(child: Text(sprintf("%s%s :", [type, title]))),
            Text(sprintf("%d/%d", [nowCredit, minCredit])),
          ],
        ),
      ),
      onTap: () {
        final result = courseScoreCredit.getCourseByType(type);
        final List<String> courseInfoList = [];

        for (final courseScoreInfoEntry in result.entries) {
          courseInfoList.add(courseScoreInfoEntry.key);
          for (final course in courseScoreInfoEntry.value) {
            courseInfoList.add(sprintf("     %s", [course.name]));
          }
        }

        if (courseInfoList.isNotEmpty) {
          Get.dialog(
            AlertDialog(
              title: Text(R.current.creditInfo),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: courseInfoList.length,
                  itemBuilder: (_, index) {
                    return SizedBox(height: 35, child: Text(courseInfoList[index]));
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back();
                  },
                  child: Text(R.current.sure),
                ),
              ],
            ),
            barrierDismissible: true,
            transitionDuration: _isDesktop ? const Duration(milliseconds: 160) : null,
          );
        }
      },
    );
  }

  Widget _buildOneLineCourse(String name, String openClass) => Padding(
    padding: const EdgeInsets.all(5),
    child: Row(
      children: [
        Expanded(child: Text(name)),
        Text(openClass),
      ],
    ),
  );

  Widget _buildSemesterScores(SemesterCourseScoreJson courseScore) {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: CourseScoreSection(scoreInfoList: courseScore.courseScoreList),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: SemesterScoreGradeMetrics(
          totalAverageScoreValue: courseScore.getAverageScoreString(),
          performanceScoreValue: courseScore.getPerformanceScoreString(),
          totalCreditValue: courseScore.getTotalCreditString(),
          creditsEarnedValue: courseScore.getTakeCreditString(),
        ),
      ),
      _buildRankMetrics(courseScore),
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: _isDesktop
          ? Column(children: children)
          : AnimationLimiter(
              child: Column(
                children: AnimationConfiguration.toStaggeredList(
                  childAnimationBuilder: (widget) =>
                      SlideAnimation(verticalOffset: 50.0, child: FadeInAnimation(child: widget)),
                  children: children,
                ),
              ),
            ),
    );
  }

  Widget _buildRankMetrics(SemesterCourseScoreJson courseScore) => (courseScore.isRankEmpty)
      ? Text(R.current.noRankInfo, style: const TextStyle(fontSize: 24))
      : Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: RankGradeMetrics(title: R.current.semesterRanking, rankInfo: courseScore.now),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: RankGradeMetrics(title: R.current.previousRankings, rankInfo: courseScore.history),
            ),
          ],
        );
}

class _DesktopScoreLoadingBadge extends StatelessWidget {
  const _DesktopScoreLoadingBadge({this.progress, this.label});

  final double? progress;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progressValue = progress;
    final progressLabel = label?.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: RepaintBoundary(child: CircularProgressIndicator(value: progressValue, strokeWidth: 2.2)),
            ),
            if (progressLabel != null && progressLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(progressLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
