import 'package:flutter/material.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/ui/pages/coursedetail/screen/course_info_page.dart';
import 'package:qaq_app/ui/pages/coursedetail/screen/ischoolplus/iplus_file_page.dart';

class DesktopCourseInspector extends StatefulWidget {
  const DesktopCourseInspector({super.key, required this.studentId, required this.courseInfo, required this.onClose});

  final String studentId;
  final CourseInfoJson courseInfo;
  final VoidCallback onClose;

  @override
  State<DesktopCourseInspector> createState() => _DesktopCourseInspectorState();
}

class _DesktopCourseInspectorState extends State<DesktopCourseInspector> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final courseName = widget.courseInfo.main.course.name;
    final isOwnCourse = widget.studentId == LocalStorage.instance.getAccount();
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.65);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border.all(color: borderColor),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    courseName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment<int>(value: 0, icon: const Icon(Icons.info_outline), label: Text(R.current.details)),
                ButtonSegment<int>(
                  value: 1,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(R.current.fileAndVideo),
                ),
              ],
              selected: {_index},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _index = selection.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _index == 0
                ? CourseInfoPage(widget.studentId, widget.courseInfo)
                : isOwnCourse
                ? IPlusFilePage(widget.studentId, widget.courseInfo, desktopMode: true)
                : Center(child: Text(R.current.notSupport)),
          ),
        ],
      ),
    );
  }
}
