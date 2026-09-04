import 'account_status.dart';

class SimpleLoginResult {
  final bool isSuccess;
  final AccountStatus accountStatus;
  final String errorMessage;
  final bool resetPassword;
  final String userNaturalName;
  final String userMail;
  final String userPhotoName;
  final String userDn;
  final String passwordExpiredRemind;
  final String sessionId;

  const SimpleLoginResult({
    required this.isSuccess,
    required this.accountStatus,
    required this.errorMessage,
    required this.resetPassword,
    required this.userNaturalName,
    required this.userMail,
    required this.userPhotoName,
    required this.userDn,
    required this.passwordExpiredRemind,
    required this.sessionId,
  });

  factory SimpleLoginResult.fromJson(Map<String, dynamic> json) {
    final success = _asBool(json['success']);
    final errorMessage = _asString(json['errorMsg']);
    final resetPassword = _asBool(json['resetPwd']);
    final passwordExpiredRemind = _asString(json['passwordExpiredRemind']);

    final AccountStatus accountStatus;
    if (errorMessage.contains('密碼錯誤')) {
      accountStatus = AccountStatus.receivedInvalidCredential;
    } else if (errorMessage.contains('已被鎖住')) {
      accountStatus = AccountStatus.locked;
    } else if (resetPassword && errorMessage.contains('密碼已過期')) {
      accountStatus = AccountStatus.passwordExpired;
    } else if (!success && errorMessage.contains('驗證手機')) {
      accountStatus = AccountStatus.needsVerifyMobile;
    } else if (!success) {
      accountStatus = AccountStatus.unknown;
    } else if (passwordExpiredRemind.trim().isNotEmpty) {
      accountStatus = AccountStatus.passwordWillExpired;
    } else {
      accountStatus = AccountStatus.normal;
    }

    final isSuccess = success &&
        (accountStatus == AccountStatus.normal || accountStatus == AccountStatus.passwordWillExpired);

    return SimpleLoginResult(
      isSuccess: isSuccess,
      accountStatus: accountStatus,
      errorMessage: errorMessage,
      resetPassword: resetPassword,
      userNaturalName: _asString(json['givenName']),
      userMail: _asString(json['userMail']),
      userPhotoName: _asString(json['userPhoto']),
      userDn: _asString(json['userDn']),
      passwordExpiredRemind: passwordExpiredRemind,
      sessionId: _asString(json['sessionId']),
    );
  }

  static String _asString(dynamic value) => value?.toString() ?? '';

  static bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }
}
