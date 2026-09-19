import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/model/course/course_score_json.dart';

class ScoreTile extends StatelessWidget {
  ScoreTile({
    super.key,
    required this.courseName,
    required this.category,
    required this.scoreValue,
  });

  /// The score value of a course.
  /// Note that we should make the score's type to be a [String] instead of [int] since the score can be a string like "Q".
  final String scoreValue;
  final String category;
  final String courseName;

  final ValueNotifier<int?> _selectedCategory = ValueNotifier(null);

  int? _getInitialCategoryIndex() {
    final index = constCourseType.indexOf(category);
    return index == -1 ? null : index;
  }

  Widget get _courseNameText => AutoSizeText(courseName, style: const TextStyle(fontSize: 16.0));

  Widget get _categoryMenu => ValueListenableBuilder(
    valueListenable: _selectedCategory,
    builder: (_, value, _) => DropdownButton(
      underline: const SizedBox.shrink(),
      value: value ?? _getInitialCategoryIndex(),
      items: constCourseType
          .asMap()
          .entries
          .map((category) => _buildCategoryMenuItem(category.value, category.key))
          .toList(),
      onChanged: (newCategory) {
        _selectedCategory.value = newCategory;
      },
    ),
  );

  Widget get _scoreValueText => SizedBox(
    width: 40,
    child: Text(scoreValue, style: const TextStyle(fontSize: 16.0), textAlign: TextAlign.end),
  );

  DropdownMenuItem<int> _buildCategoryMenuItem(String category, int index) => DropdownMenuItem(
    value: index,
    child: Text(category, style: const TextStyle(fontSize: 16.0)),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(child: _courseNameText),
      if (category.isNotEmpty) _categoryMenu,
      _scoreValueText,
    ],
  );
}
