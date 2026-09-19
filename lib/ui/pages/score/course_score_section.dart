import 'package:flutter/material.dart';
import 'package:flutter_app/src/model/course/course_score_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/ui/pages/score/widgets/score_tile_widget.dart';
import 'package:flutter_app/ui/pages/score/widgets/metrics_title_widget.dart';

class CourseScoreSection extends StatelessWidget {
  const CourseScoreSection({super.key, required this.scoreInfoList});

  final List<CourseScoreInfoJson> scoreInfoList;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      MetricsTitle(title: R.current.resultsOfVariousSubjects),
      ListView.builder(
        shrinkWrap: true,
        itemCount: scoreInfoList.length,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, index) {
          final scoreInfo = scoreInfoList[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ScoreTile(courseName: scoreInfo.name, category: scoreInfo.category, scoreValue: scoreInfo.score),
          );
        },
      ),
    ],
  );
}
