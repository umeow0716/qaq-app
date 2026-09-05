import 'package:flutter_app/ui/other/msg_dialog.dart';
import 'package:flutter_app/ui/other/my_progress_dialog.dart';
import 'package:get/get.dart';

import 'task.dart';

class DialogTask<T> extends Task<T> {
  DialogTask(super.name);
  bool openLoadingDialog = true;
  bool openErrorDialog = true;
  String? errorMessage;

  @override
  Future<TaskStatus> execute() async {
    return TaskStatus.success;
  }

  void onStart(String message) {
    if (openLoadingDialog) {
      MyProgressDialog.progressDialog(message);
    }
  }

  void onEnd() {
    if (openLoadingDialog) {
      MyProgressDialog.hideProgressDialog();
    }
  }

  Future<TaskStatus> onError(String message) async {
    errorMessage = message;
    final parameter = MsgDialogParameter(desc: message, dialogType: DialogType.warning);
    return await onErrorParameter(parameter);
  }

  Future<TaskStatus> onErrorParameter(MsgDialogParameter parameter) async {
    errorMessage = parameter.desc;
    if (openErrorDialog) {
      MsgDialog(parameter).show();
    }

    // Return GiveUp here instead of Restart to prevent the Un-terminated error stack.
    return TaskStatus.shouldGiveUp;
  }

  /// Helps to show an [MsgDialog] before the current [Context] is popped.
  /// This is useful when we have to show some dialogs after the route is changed.
  Future<TaskStatus> msgDialogShownResult({
    required MsgDialogParameter msgDialogParam,
    required TaskStatus result,
  }) async {
    errorMessage = msgDialogParam.desc;
    if (openErrorDialog) {
      await Get.asap(() => MsgDialog(msgDialogParam).show());
    }
    return result;
  }
}
