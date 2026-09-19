import 'package:qaq_app/src/portal/account_status.dart';
import 'package:qaq_app/src/portal/simple_login_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SimpleLoginResult parse({
    bool success = false,
    String errorMsg = '',
    bool resetPwd = false,
    String? passwordExpiredRemind,
  }) => SimpleLoginResult.fromJson({
    'success': success,
    'errorMsg': errorMsg,
    'resetPwd': resetPwd,
    'passwordExpiredRemind': passwordExpiredRemind,
    'givenName': 'Test User',
    'userMail': 'test@ntut.edu.tw',
    'userPhoto': '',
    'userDn': 'cn=test',
    'sessionId': 'session',
  });

  test('successful login is normal', () {
    final result = parse(success: true);
    expect(result.isSuccess, isTrue);
    expect(result.accountStatus, AccountStatus.normal);
  });

  test('wrong password maps to invalid credential', () {
    final result = parse(errorMsg: '密碼錯誤');
    expect(result.isSuccess, isFalse);
    expect(result.accountStatus, AccountStatus.receivedInvalidCredential);
  });

  test('locked account maps to locked', () {
    expect(parse(errorMsg: '帳號已被鎖住').accountStatus, AccountStatus.locked);
  });

  test('expired password requires reset flag and message', () {
    expect(parse(errorMsg: '密碼已過期', resetPwd: true).accountStatus, AccountStatus.passwordExpired);
  });

  test('mobile verification is a failed login', () {
    final result = parse(errorMsg: '請驗證手機');
    expect(result.isSuccess, isFalse);
    expect(result.accountStatus, AccountStatus.needsVerifyMobile);
  });

  test('password expiry reminder keeps login successful', () {
    final result = parse(success: true, passwordExpiredRemind: '7 days');
    expect(result.isSuccess, isTrue);
    expect(result.accountStatus, AccountStatus.passwordWillExpired);
  });
}
