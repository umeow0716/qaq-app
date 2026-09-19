import 'package:flutter/material.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/ui/pages/score/widgets/grade_metrics_cell_widget.dart';
import 'package:qaq_app/ui/pages/score/widgets/metrics_title_widget.dart';

class SemesterScoreGradeMetrics extends StatelessWidget {
  const SemesterScoreGradeMetrics({
    super.key,
    required this.totalAverageScoreValue,
    required this.performanceScoreValue,
    required this.totalCreditValue,
    required this.creditsEarnedValue,
  });

  final String totalAverageScoreValue;
  final String performanceScoreValue;
  final String totalCreditValue;
  final String creditsEarnedValue;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      MetricsTitle(title: R.current.semesterGrades),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 3,
        children: [
          GradeMetricsCell(name: R.current.totalAverage, value: totalAverageScoreValue),
          GradeMetricsCell(name: R.current.performanceScores, value: performanceScoreValue),
          GradeMetricsCell(name: R.current.practiceCredit, value: totalCreditValue),
          GradeMetricsCell(name: R.current.creditsEarned, value: creditsEarnedValue),
        ],
      ),
    ],
  );
}
