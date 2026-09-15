import 'package:flutter_app/src/connector/ischool_plus_connector.dart';
import 'package:flutter_app/src/connector/ischool_plus_access_guard.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:flutter_app/src/task/ntut/ntut_task.dart';
import 'package:flutter_app/src/task/task.dart';
import 'package:flutter_app/ui/other/msg_dialog.dart';

class IPlusSystemTask<T> extends NTUTTask<T> {
  IPlusSystemTask(
    String name, {
    this.showNetworkUnavailable = true,
    this.allowAutoVpn = true,
  }) : super("IPlusSystemTask $name");

  final bool showNetworkUnavailable;
  final bool allowAutoVpn;
  static bool isLogin = false;

  @override
  Future<TaskStatus> execute() async {
    final status = await super.execute();
    if (status != TaskStatus.success) return status;

    final accessRoute = await IStudyAccessGuard.route();
    if (accessRoute == IStudyAccessRoute.blocked) {
      if (!showNetworkUnavailable) return TaskStatus.shouldGiveUp;
      return onErrorParameter(
        MsgDialogParameter(
          title: IStudyAccessGuard.blockedTitle,
          desc: IStudyAccessGuard.blockedMessage,
          dialogType: DialogType.warning,
          removeCancelButton: true,
        ),
      );
    }
    if (accessRoute == IStudyAccessRoute.vpn && !allowAutoVpn) {
      return TaskStatus.shouldGiveUp;
    }

    if (isLogin) return TaskStatus.success;

    if (status == TaskStatus.success) {
      isLogin = true;

      super.onStart(R.current.loginISchoolPlus);
      final studentId = LocalStorage.instance.getAccount();
      final value = await ISchoolPlusConnector.login(studentId);
      super.onEnd();

      //TODO: generate string for this
      switch (value) {
        case ISchoolPlusConnectorStatus.loginGetSSOIndexError:
          return onError("ischool login get SSO index error");
        case ISchoolPlusConnectorStatus.loginRedirectionError:
          return onError("ischool login redirection error");
        default:
          break;
      }
    }
    return status;
  }

  @override
  Future<TaskStatus> onError(String message) {
    isLogin = false;
    return super.onError(message);
  }

  @override
  Future<TaskStatus> onErrorParameter(MsgDialogParameter parameter) {
    isLogin = false;
    return super.onErrorParameter(parameter);
  }
}
