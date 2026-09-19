import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/model/ntut/ap_tree_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/task/ntut/ntut_task.dart';

import '../task.dart';

class NTUTSubSystemTask extends NTUTTask<APTreeJson> {
  final String? arg;

  NTUTSubSystemTask(this.arg) : super("NTUTSubSystemTask");

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status == TaskStatus.success) {
      final value = await NTUTConnector.getTree(arg);
      if (value != null) {
        result = value;
        return TaskStatus.success;
      } else {
        return super.onError(R.current.error);
      }
    }
    return status;
  }
}
