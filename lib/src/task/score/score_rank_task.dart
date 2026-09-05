import 'package:flutter_app/src/connector/score_connector.dart';
import 'package:flutter_app/src/model/course/course_score_json.dart';
import 'package:flutter_app/src/r.dart';

import '../task.dart';
import 'score_system_task.dart';

class ScoreRankTask extends ScoreSystemTask<List<SemesterCourseScoreJson>> {
  ScoreRankTask() : super("ScoreRankTask");

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status == TaskStatus.success) {
      try {
        super.onStart(R.current.getScoreRank);
        final value = await ScoreConnector.getScoreRankList();
        super.onEnd();

        result = value;
        return TaskStatus.success;
      } catch (e) {
        if (e is FormatException) {
          return super.onError(R.current.getScoreRankQuestionnaireError);
        } else {
          return super.onError(R.current.getScoreRankError);
        }
      }
    }
    return status;
  }
}
